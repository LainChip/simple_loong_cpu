`include "common.svh"
`include "decoder.svh"
`include "pipeline.svh"
`include "lsu_types.svh"
`include "bpu.svh"

module frontend(
	input clk,
	input rst_n,

	// 指令输出
	output  inst_t [1:0] inst_o,
	output  logic  [1:0] inst_valid_o,
	input logic    [1:0] issue_num_i, // 0, 1, 2
	input logic          backend_stall_i, 

	// BPU 反馈
	input bpu_update_t bpu_feedback_i,

    // 特权控制信号
    output priv_resp_t priv_resp_o,
    input priv_req_t priv_req_i,

	// 访存总线
    output cache_bus_req_t bus_req_o,       // cache的访问请求
    input cache_bus_resp_t bus_resp_i,        // cache的访问应答

	// MMU 访问信号
	output mmu_s_req_t mmu_req_o,
	input mmu_s_resp_t mmu_resp_i
);
    // 这个function应该放在前端，在fetch阶段和写入fifo阶段之间，合成inst_t的阶段进行。
    function register_info_t get_register_info(
        input decode_info_t decode_info
    );
        register_info_t ret;
        case(decode_info.is.reg_type)
            `_REG_TYPE_I:begin
                ret.r_reg[0] = '0;
                ret.r_reg[1] = '0;
                ret.w_reg = '0;
            end
            `_REG_TYPE_RW:begin
                ret.r_reg[0] = '0;
                ret.r_reg[1] = decode_info.general.inst25_0[9:5];
                ret.w_reg = decode_info.general.inst25_0[4:0];
            end
            `_REG_TYPE_RRW:begin
                ret.r_reg[0] = decode_info.general.inst25_0[14:10];
                ret.r_reg[1] = decode_info.general.inst25_0[9:5];
                ret.w_reg = decode_info.general.inst25_0[4:0];
            end
            `_REG_TYPE_W:begin
                ret.r_reg[0] = decode_info.general.inst25_0[14:10];
                ret.r_reg[1] = decode_info.general.inst25_0[9:5];
                ret.w_reg = decode_info.general.inst25_0[4:0];
            end
            `_REG_TYPE_RR:begin
                ret.r_reg[0] = decode_info.general.inst25_0[4:0];
                ret.r_reg[1] = decode_info.general.inst25_0[9:5];
                ret.w_reg = '0;
            end
            `_REG_TYPE_BL:begin
                ret.r_reg[0] = '0;
                ret.r_reg[1] = '0;
                ret.w_reg = 5'd1;
            end
            `_REG_TYPE_CSRXCHG:begin
                ret.r_reg[0] = decode_info.general.inst25_0[4:0];
                ret.r_reg[1] = decode_info.general.inst25_0[9:5];
                ret.w_reg = decode_info.general.inst25_0[4:0];
            end
            `_REG_TYPE_RDCNTID:begin
                ret.r_reg[0] = '0;
                ret.r_reg[1] = '0;
                ret.w_reg = decode_info.general.inst25_0[4:0] | decode_info.general.inst25_0[9:5];
            end
            `_REG_TYPE_INVTLB:begin
                ret.r_reg[0] = decode_info.general.inst25_0[14:10];
                ret.r_reg[1] = decode_info.general.inst25_0[9:5];
                ret.w_reg = '0;
            end
            default:begin
                ret.r_reg[0] = '0;
                ret.r_reg[1] = '0;
                ret.w_reg = '0;
            end
        endcase
        return ret;
    endfunction


    fetch_excp_t fetch_excp;
    bpu_predict_t[1:0] fetch_predict_fifo,fifo_predict;
    bpu_predict_t bpu_predict,fetch_predict;
    decode_info_t [1:0]fifo_decode_info;
    logic [31:0] bpu_vpc,bpu_ppc,fetch_vpc,fifo_vpc;
    logic [1:0] bpu_pc_valid,fetch_pc_valid,fetch_valid;
    logic frontend_clr, bpu_stall, bpu_stall_req,icache_ready,fetch_ready,fifo_ready;

    logic[1:0][31:0] fetch_inst,fetch_inst_fifo;
    logic[1:0][63 + $bits(bpu_predict_t) + $bits(fetch_excp_t):0] fetch_fifo_out;
    inst_t [1:0] fifo_inst;
    logic [1:0] fifo_write_num,fetch_write_num;

    // NPC / BPU 模块
    npc npc_module(
        .clk,
        .rst_n,
        .stall_i(bpu_stall),
        .update_i(bpu_feedback_i),
        .predict_o(bpu_predict),
        .pc_o(bpu_vpc),
        .stall_o(bpu_stall_req)
    );

    assign bpu_pc_valid = {~frontend_clr & rst_n , ~frontend_clr & ~bpu_vpc[2] & rst_n};


    // bpu inst_bpu
    // (
    //     .clk,
    //     .rst_n,
    //     .stall_i(bpu_stall),
    //     .update_i(bpu_feedback_i),
    //     .predict_o(bpu_predict),
    //     .pc_o(bpu_vpc),
    //     .stall_o(bpu_stall_req),
    //     .pc_valid_o(bpu_pc_valid)
    // );


    // 暂停以及清零控制逻辑
    assign frontend_clr = bpu_feedback_i.flush;
    assign bpu_stall = ~icache_ready | bpu_stall_req;
    // I CACHE 模块
    icache #(
        .FETCH_SIZE(2),
        .ATTACHED_INFO_WIDTH($bits(bpu_predict_t))
    ) icache_module(
        .clk,    // Clock
        .rst_n,  // Asynchronous reset active low
        
        .cacheop_i('0 /*TODO*/),
        .cacheop_valid_i('0 /*TODO*/),
        .cacheop_ready_o(/*NOT CONNECT TODO*/),

        .vpc_i(bpu_vpc),
        .valid_i(bpu_pc_valid),
        .attached_i(bpu_predict),

        .vpc_o(fetch_vpc),
        .ppc_o(/*NOT CONNECT*/),
        .valid_o(fetch_pc_valid),
        .attached_o(fetch_predict),
        // .decode_output_o(fetch_decode_info),
        .inst_o(fetch_inst),
        .fetch_excp_o(fetch_excp),

        .ready_i(fetch_ready),
        .ready_o(icache_ready),
        .clr_i(frontend_clr),

        .bus_req_o,
        .bus_resp_i
    );


    // FIFO 模块
    multi_channel_fifo #(
        .DATA_WIDTH(64 + $bits(bpu_predict_t) + $bits(fetch_excp_t)),
        .DEPTH(8),
        .BANK(4),
        .WRITE_PORT(2),
        .READ_PORT(2)
    ) inst_fifo(
        .clk,
        .rst_n,

        .flush_i(frontend_clr),

        .write_valid_i(1'b1),
        .write_ready_o(fetch_ready),
        .write_num_i (fetch_write_num),
        .write_data_i({fetch_excp,fetch_predict_fifo[1],fetch_vpc[31:3],1'b1,fetch_vpc[1:0],fetch_inst_fifo[1],fetch_excp,fetch_predict_fifo[0],fetch_vpc[31:3],~fetch_pc_valid[0],fetch_vpc[1:0],fetch_inst_fifo[0]}),

        .read_valid_o(fetch_valid),
        .read_ready_i(fifo_ready),
        .read_num_i(fifo_write_num),
        .read_data_o(fetch_fifo_out)
    );

    // INST 选择逻辑
    always_comb begin
        fetch_write_num = {fetch_pc_valid[1] & fetch_pc_valid[0], fetch_pc_valid[1] ^ fetch_pc_valid[0]};
        fetch_inst_fifo[0] = (fetch_pc_valid[0]) ? fetch_inst[0] : fetch_inst[1];
        fetch_inst_fifo[1] = fetch_inst[1];
        fetch_predict_fifo[0] = fetch_predict;
        fetch_predict_fifo[1] = fetch_predict;
    end

    // INST 结构体组装模块
	decoder decoder_module_0(
		.inst_i(fetch_fifo_out[0][31:0]),
		.decode_info_o(fifo_decode_info[0]),
		.inst_string_o(/*NC*/)
	);
	decoder decoder_module_1(
		.inst_i(fetch_fifo_out[1][31:0]),
		.decode_info_o(fifo_decode_info[1]),
		.inst_string_o(/*NC*/)
	);

    always_comb begin
        fifo_write_num = {fetch_valid[0] & fetch_valid[1], fetch_valid[0] ^ fetch_valid[1]};
        fifo_inst[0].bpu_predict = fetch_fifo_out[0][63+$bits(bpu_predict_t):64];
        fifo_inst[0].decode_info = fifo_decode_info[0];
        fifo_inst[0].pc = fetch_fifo_out[0][63:32];
        fifo_inst[0].valid = 1'b1;
        fifo_inst[0].register_info = get_register_info(fifo_decode_info[0]);
        fifo_inst[0].fetch_excp = fetch_fifo_out[0][63+$bits(bpu_predict_t)+$bits(fetch_excp_t):64+$bits(bpu_predict_t)];
        fifo_inst[1].bpu_predict = fetch_fifo_out[1][63+$bits(bpu_predict_t):64];
        fifo_inst[1].decode_info = fifo_decode_info[1];
        fifo_inst[1].pc = fetch_fifo_out[1][63:32];
        fifo_inst[1].valid = 1'b1;
        fifo_inst[1].register_info = get_register_info(fifo_decode_info[1]);
        fifo_inst[1].fetch_excp = fetch_fifo_out[1][63+$bits(bpu_predict_t)+$bits(fetch_excp_t):64+$bits(bpu_predict_t)];
    end

    multi_channel_fifo #(
        .DATA_WIDTH($bits(inst_t)),
        .DEPTH(2),
        .BANK(2),
        .WRITE_PORT(2),
        .READ_PORT(2)
    ) decoded_fifo(
        .clk,
        .rst_n,

        .flush_i(frontend_clr),

        .write_valid_i(1'b1),
        .write_ready_o(fifo_ready),
        .write_num_i (fifo_write_num),
        .write_data_i(fifo_inst),

        .read_valid_o(inst_valid_o),
        .read_ready_i(~backend_stall_i),
        .read_num_i(issue_num_i),
        .read_data_o(inst_o)
    );

endmodule
