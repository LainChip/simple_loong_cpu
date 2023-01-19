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
    input cache_bus_resp_t bus_resp_i        // cache的访问应答
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
                ret.r_reg[1] = '0;
                ret.w_reg = decode_info.general.inst25_0[4:0];
            end
            `_REG_TYPE_RDCNTID:begin
                ret.r_reg[0] = '0;
                ret.r_reg[1] = '0;
                ret.w_reg = decode_info.general.inst25_0[9:5];
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

    bpu_predict_t[1:0] bpu_predict,fifo_predict;
    decode_info_t [1:0]fifo_decode_info;
    logic [31:0] bpu_vpc,bpu_ppc,fifo_vpc;
    logic [1:0] bpu_pc_valid, fifo_pc_valid;
    logic frontend_stall,frontend_clr, bpu_stall,icache_stall,fifo_ready;

    inst_t [1:0] fifo_inst;
    logic [1:0] fifo_write_num;

    // NPC / BPU 模块
    npc npc_module(
        .clk,
        .rst_n,
        .stall_i(frontend_stall),
        .update_i(bpu_feedback_i),
        .predict_o(bpu_predict),
        .pc_o(bpu_vpc),
        .stall_o(bpu_stall)
    );

    assign bpu_pc_valid = {~frontend_clr , ~frontend_clr & ~bpu_vpc[2]};

    // 暂停以及清零控制逻辑
    assign frontend_clr = bpu_feedback_i.flush;
    assign frontend_stall = (~fifo_ready) | icache_stall | bpu_stall;
    // I CACHE 模块
    icache #(
        .FETCH_SIZE(2),
        .ATTACHED_INFO_WIDTH(2 * $bits(bpu_predict_t))
    ) icache_module(
        .clk,    // Clock
        .rst_n,  // Asynchronous reset active low
        
        .vpc_i(bpu_vpc),
        .ppc_i(bpu_ppc),
        .valid_i(bpu_pc_valid),
        .attached_i(bpu_predict),

        .vpc_o(fifo_vpc),
        .ppc_o(/*NOT CONNECT*/),
        .valid_o(fifo_pc_valid),
        .attached_o(fifo_predict),
        .decode_output_o(fifo_decode_info),

        .stall_i(frontend_stall),
        .busy_o(icache_stall),
        .clr_i(frontend_clr),

        .bus_req_o,
        .bus_resp_i
    );

    // INST 结构体组装模块
    always_comb begin
        fifo_write_num = {fifo_pc_valid[0] & fifo_pc_valid[1], fifo_pc_valid[0] ^ fifo_pc_valid[1]};
        fifo_inst[0].bpu_predict = fifo_pc_valid[0] ? fifo_predict[0] : fifo_predict[1];
        fifo_inst[0].decode_info = fifo_pc_valid[0] ? fifo_decode_info[0] : fifo_decode_info[1];
        fifo_inst[0].pc = fifo_pc_valid[0] ? fifo_vpc : {fifo_vpc[31:3],3'b100};
        fifo_inst[0].valid = |fifo_pc_valid;
        fifo_inst[0].register_info = fifo_pc_valid[0] ? get_register_info(fifo_decode_info[0]) : get_register_info(fifo_decode_info[1]) ;
        fifo_inst[1].bpu_predict = fifo_predict[1];
        fifo_inst[1].decode_info = fifo_decode_info[1];
        fifo_inst[1].pc = {fifo_vpc[31:3],3'b100};
        fifo_inst[1].valid = fifo_pc_valid[0] & fifo_pc_valid[1];
        fifo_inst[1].register_info = get_register_info(fifo_decode_info[1]);
    end

    // FIFO 模块
    multi_channel_fifo #(
        .DATA_WIDTH($bits(inst_t)),
        .DEPTH(8),
        .BANK(4),
        .WRITE_PORT(2),
        .READ_PORT(2)
    ) inst_fifo(
        .clk,
        .rst_n,

        .flush_i(frontend_clr),

        .write_valid_i(~frontend_stall),
        .write_ready_o(fifo_ready),
        .write_num_i (fifo_write_num),
        .write_data_i(fifo_inst),

        .read_valid_o(inst_valid_o),
        .read_ready_i(~backend_stall_i),
        .read_num_i(issue_num_i),
        .read_data_o(inst_o)
    );

endmodule
