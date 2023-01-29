`include "common.svh"
`include "decoder.svh"
`include "pipeline.svh"
`include "lsu_types.svh"
`include "bpu.svh"

module backend(
	input clk,
	input rst_n,
    input [7:0] int_i,

	// 调试用输出信号组
	// output debug_info_t [1:0] debug_info_o,

	// 指令输入
	input  inst_t [1:0] inst_i,
	input  logic  [1:0] inst_valid_i,
	output logic  [1:0] issue_num_o, // 0, 1, 2
	output logic        backend_stall_o, 

	// BPU 输入（随指令走）
	// input bpu_predict_t [1:0] bpu_predict_i,
	output bpu_update_t bpu_feedback_o,

    // 特权控制信号
    input priv_resp_t priv_resp_i,
    output priv_req_t priv_req_o,

	// 访存总线
    output cache_bus_req_t bus_req_o,       // cache的访问请求
    input cache_bus_resp_t bus_resp_i        // cache的访问应答


);

	// 信号定义
	// 后端暂停和清零向量
	logic m2_clr_exclude_self;
	logic [1:0][2:0] stall_vec, clr_vec, stall_req, clr_req;
	logic [1:0][3:0] revert_vector_pipe;
	logic [3:0] revert_vector;
	// 前端清零向量
	logic clr_frontend;

	// 发射向量
	logic [1:0] issue;
	logic revert;

	// 发射控制流及发射数据流
	ctrl_flow_t[1:0] ctrl_flow;
	data_flow_t[1:0] data_flow;

	// 寄存器控制信号
	forwarding_info_t[1:0][1:0] forwarding_info;
	logic [1:0][4:0]  reg_w_addr;
	logic [1:0][31:0] reg_w_data;
	logic [1:0][1:0][4:0]  reg_r_addr; // reversed
	logic [1:0][1:0][31:0] reg_r_data; // reversed

	// 数据转发总线
	logic [1:0][2:0][31:0]forwarding_src;

	// ISSUE 部分，对指令进行发射
	// Issue module, judge whether we can issue or not
	issue issue_module(
		.clk(clk),
		.rst_n(rst_n),
		.inst_i(inst_i),
		.inst_valid_i(inst_valid_i),
		.stall_vec_i(stall_vec),			// 0 for ex, 1 for m1, 2 for m2
		.clr_vec_i(clr_vec),				// 0 for ex, 1 for m1, 2 for m2
		.clr_frontend_i(clr_frontend),

		.issue_o(issue), // 2'b00, 2'b01, 2'b11 三种情况，指令必须顺序发射.
		.revert_o(revert),         // send inst[0] to pipe[1], inst[1] to pipe[0]. otherwise, inst[0] to pipe[0], inst[1] to pipe[1]
		.forwarding_info_o(forwarding_info),
		.stall_i(stall_vec[0][0] | stall_vec[0][1]) // 当 EX暂停时，不可以发射
	);

	// 生成前端使用的 issue_num 信号
	assign issue_num_o = {issue[1],issue[0] & ~issue[1]};
	assign clr_frontend = bpu_feedback_o.flush;

	// Register Files module, get the operation num
	reg_file #(
		.DATA_WIDTH          (32),
		.REG_FILE_SIZE       (32),
		.REG_CONST_ZERO_SIZE (1),
		.REG_READ_PORT		 (4),
		.REG_WRITE_PORT      (2),
		.INNER_FORWARDING	 (1'b1)
	) reg_file_module(
		.clk     (clk),
		.rst_n   (rst_n),
		.w_ptr_i (reg_w_addr),
		.w_data_i(reg_w_data),

		.r_ptr_i (reg_r_addr),
		.r_data_o(reg_r_data)
	);

	// 准备即将发射的指令和数据流
	// 控制流部分，也处理读寄存器地址 reg_r_addr
	for(genvar pipe_id = 0 ; pipe_id < 2; pipe_id += 1) begin
		inst_t inst_sel;
		assign inst_sel = inst_i[revert ^ pipe_id[0]];
		forwarding_info_t[1:0] forwarding_info_sel = forwarding_info[revert ^ pipe_id];
		always_comb begin
			ctrl_flow[pipe_id].decode_info = inst_sel.decode_info;
			ctrl_flow[pipe_id].bpu_predict = inst_sel.bpu_predict;
			ctrl_flow[pipe_id].w_reg = inst_sel.register_info.w_reg;
			ctrl_flow[pipe_id].forwarding_info = forwarding_info_sel;
			ctrl_flow[pipe_id].revert = revert;
			reg_r_addr[pipe_id] = inst_sel.register_info.r_reg;
			data_flow[pipe_id].pc = inst_sel.pc;
			data_flow[pipe_id].reg_data = reg_r_data[pipe_id];
			data_flow[pipe_id].result = '0;
		end
	end

	// 生成两个不对称的pipe

	backend_pipeline #(
	.MAIN_PIPE(1'b1)
	) pipeline_0 (
	.clk,    // Clock
	.rst_n,  // Asynchronous reset active low

	// 控制用暂停信号
	.stall_vec_i(stall_vec[0]), // 0 for ex, 1 for m1, 2 for m2
	.clr_vec_i(clr_vec[0]),   // 0 for ex, 1 for m1, 2 for m2

	// 暂停请求
	.ex_stall_req_o(stall_req[0][0]), // TODO
	.m1_stall_req_o(stall_req[0][1]),
	.m2_stall_req_o(stall_req[0][2]),
	.m2_clr_exclude_self_o(m2_clr_exclude_self),

	.revert_vector_o(revert_vector_pipe[0]),
	.ex_clr_req_o(clr_req[0][0]),
	.m1_clr_req_o(clr_req[0][1]),
	.m2_clr_req_o(clr_req[0][2]),

	.revert_i(revert),
	.issue_i((issue[0] & !revert) | (issue[1] & revert)),
	.ctrl_flow_i(ctrl_flow[0]),
	.data_flow_i(data_flow[0]),

	// FORWARDING DATA SOURCE
	.forwarding_src_i(forwarding_src),

	// FORWARDING DATA OUTPUT
	.forwarding_data_o(forwarding_src[0]),

	.reg_w_addr_o(reg_w_addr[0]),
	.reg_w_data_o(reg_w_data[0]),
	
	// FOR MAIN PIPE
	.bus_req_o,         // cache的访问请求
    .bus_resp_i,        // cache的访问应答
    .priv_resp_i,
    .priv_req_o,
    .bpu_feedback_o
	);

	backend_pipeline #(
	.MAIN_PIPE(1'b0)
	) pipeline_1 (
	.clk,    // Clock
	.rst_n,  // Asynchronous reset active low

	// 控制用暂停信号
	.stall_vec_i(stall_vec[1]), // 0 for ex, 1 for m1, 2 for m2
	.clr_vec_i(clr_vec[1]),   // 0 for ex, 1 for m1, 2 for m2

	// 暂停请求
	.ex_stall_req_o(stall_req[1][0]), // TODO
	.m1_stall_req_o(stall_req[1][1]),
	.m2_stall_req_o(stall_req[1][2]),
	// .m2_clr_exclude_self_o(/*NOT CONNECT*/),

	.revert_vector_o(revert_vector_pipe[1]),
	.ex_clr_req_o(clr_req[1][0]),
	.m1_clr_req_o(clr_req[1][1]),
	.m2_clr_req_o(clr_req[1][2]),

	.revert_i(revert),
	.issue_i((issue[1] & !revert) | (issue[0] & revert)),
	.ctrl_flow_i(ctrl_flow[1]),
	.data_flow_i(data_flow[1]),

	// FORWARDING DATA SOURCE
	.forwarding_src_i(forwarding_src),

	// FORWARDING DATA OUTPUT
	.forwarding_data_o(forwarding_src[1]),

	.reg_w_addr_o(reg_w_addr[1]),
	.reg_w_data_o(reg_w_data[1]),
	
	// FOR MAIN PIPE
	.bus_req_o(/*NOT CONNECT*/),       // cache的访问请求
    .bus_resp_i(/*NOT CONNECT*/),        // cache的访问应答
    .priv_resp_i(/*NOT CONNECT*/),
    .priv_req_o(/*NOT CONNECT*/),
    .bpu_feedback_o(/*NOT CONNECT*/)
	);

	// 暂停及清零控制器
	always_comb begin
		// 对于暂停的控制，如果某一流水线级请求暂停，则此流水线级 以及之前的所有流水线级 都需要暂停
		// 两条流水线同时进行暂停控制
		for(integer level = 0; level < 3; level += 1) begin //ex m1 m2
			stall_vec[0][level] = '0;
			stall_vec[1][level] = '0;
			for(integer level_req = level; level_req < 3; level_req += 1) begin
				stall_vec[0][level] |= stall_req[0][level_req] | stall_req[1][level_req];
				stall_vec[1][level] |= stall_req[0][level_req] | stall_req[1][level_req];
			end
		end
	end
	always_comb begin
		// 对于清零的控制，稍显麻烦。
		// 如果某一流水线级别请求清零，则此流水线之前的所有流水线级都需要清零。
		// 按照设计，目前只有第一条管线可以触发清零操作，
		// 对于revert的流水线级发生清零，pipe 1管线的指令执行先于pipe 0，则两条指令需要同时清零
		// 否之，只需要清零pipe 0管线的指令即可。
		for(integer level = 0; level < 3; level += 1) begin //ex m1 m2
			clr_vec[0][level] = '0;
			clr_vec[1][level] = '0;
			for(integer level_req = level + 1; level_req < 3; level_req += 1) begin
				clr_vec[0][level] |= clr_req[0][level_req];
				clr_vec[1][level] |= clr_req[0][level_req];
			end
			clr_vec[0][level] |= (level == 0) ? '0 : (clr_req[0][level] & ~m2_clr_exclude_self);
			clr_vec[1][level] |= clr_req[0][level] & ~revert_vector[level];
		end
	end
	assign revert_vector = revert_vector_pipe[0] | revert_vector_pipe[1];

`ifdef _DIFFTEST_ENABLE
ctrl_flow_t [1:0]wb_ctrl_flow;
data_flow_t [1:0]wb_data_flow;
assign wb_ctrl_flow = {pipeline_1.wb_ctrl_flow,pipeline_0.wb_ctrl_flow};
assign wb_data_flow = {pipeline_1.wb_data_flow,pipeline_0.wb_data_flow};
DifftestInstrCommit DifftestInstrCommit_0(
    .clock              (clk           ),
    .coreid             ('0),
    .index              (wb_ctrl_flow[0].revert ? 1:0),
    .valid              (wb_ctrl_flow[0].decode_info.wb.valid),
    .pc                 (wb_data_flow[0].pc),
    .instr              (wb_ctrl_flow[0].decode_info.wb.debug_inst),
    .skip               (0),
    .is_TLBFILL         ('0/*TODO*/),
    .TLBFILL_index      ('0/*TODO*/),
    .is_CNTinst         ('0/*TODO*/),
    .timer_64_value     ('0/*TODO*/),
    .wen                (wb_ctrl_flow[0].w_reg != '0),
    .wdest              (wb_ctrl_flow[0].w_reg),
    .wdata              (wb_data_flow[0].result),
    .csr_rstat          (wb_ctrl_flow[0].decode_info.m2.csr_write_en),
    .csr_data           (reg_w_data[0])
);
DifftestInstrCommit DifftestInstrCommit_1(
    .clock              (clk           ),
    .coreid             ('0),
    .index              (wb_ctrl_flow[0].revert ? 0:1),
    .valid              (wb_ctrl_flow[1].decode_info.wb.valid),
    .pc                 (wb_data_flow[1].pc),
    .instr              (wb_ctrl_flow[1].decode_info.wb.debug_inst),
    .skip               (0),
    .is_TLBFILL         ('0/*TODO*/),
    .TLBFILL_index      ('0/*TODO*/),
    .is_CNTinst         ('0/*TODO*/),
    .timer_64_value     ('0/*TODO*/),
    .wen                (wb_ctrl_flow[1].w_reg != '0),
    .wdest              (wb_ctrl_flow[1].w_reg),
    .wdata              (wb_data_flow[1].result),
    .csr_rstat          ('0/*TODO*/),
    .csr_data           ('0/*TODO*/)
);

DifftestTrapEvent DifftestTrapEvent(
    .clock              (clk           ),
    .coreid             (0              ),
    .valid              ('0/*TODO*/),
    .code               ('0/*TODO*/),
    .pc                 ('0/*TODO*/),
    .cycleCnt           ('0/*TODO*/),
    .instrCnt           ('0/*TODO*/)
);

DifftestStoreEvent DifftestStoreEvent(
    .clock              (clk           ),
    .coreid             (0              ),
    .index              (0              ),
    .valid              ('0/*TODO*/),
    .storePAddr         ('0/*TODO*/),
    .storeVAddr         ('0/*TODO*/),
    .storeData          ('0/*TODO*/)
);

DifftestLoadEvent DifftestLoadEvent(
    .clock              (clk           ),
    .coreid             (0              ),
    .index              (0              ),
    .valid              ('0/*TODO*/),
    .paddr              ('0/*TODO*/),
    .vaddr              ('0/*TODO*/)
);

DifftestGRegState DifftestGRegState(
    .clock              (clk       ),
    .coreid             (0          ),
    .gpr_0              (reg_file_module.regs_update[0]),
    .gpr_1              (reg_file_module.regs_update[1]),
    .gpr_2              (reg_file_module.regs_update[2]),
    .gpr_3              (reg_file_module.regs_update[3]),
    .gpr_4              (reg_file_module.regs_update[4]),
    .gpr_5              (reg_file_module.regs_update[5]),
    .gpr_6              (reg_file_module.regs_update[6]),
    .gpr_7              (reg_file_module.regs_update[7]),
    .gpr_8              (reg_file_module.regs_update[8]),
    .gpr_9              (reg_file_module.regs_update[9]),
    .gpr_10             (reg_file_module.regs_update[10]),
    .gpr_11             (reg_file_module.regs_update[11]),
    .gpr_12             (reg_file_module.regs_update[12]),
    .gpr_13             (reg_file_module.regs_update[13]),
    .gpr_14             (reg_file_module.regs_update[14]),
    .gpr_15             (reg_file_module.regs_update[15]),
    .gpr_16             (reg_file_module.regs_update[16]),
    .gpr_17             (reg_file_module.regs_update[17]),
    .gpr_18             (reg_file_module.regs_update[18]),
    .gpr_19             (reg_file_module.regs_update[19]),
    .gpr_20             (reg_file_module.regs_update[20]),
    .gpr_21             (reg_file_module.regs_update[21]),
    .gpr_22             (reg_file_module.regs_update[22]),
    .gpr_23             (reg_file_module.regs_update[23]),
    .gpr_24             (reg_file_module.regs_update[24]),
    .gpr_25             (reg_file_module.regs_update[25]),
    .gpr_26             (reg_file_module.regs_update[26]),
    .gpr_27             (reg_file_module.regs_update[27]),
    .gpr_28             (reg_file_module.regs_update[28]),
    .gpr_29             (reg_file_module.regs_update[29]),
    .gpr_30             (reg_file_module.regs_update[30]),
    .gpr_31             (reg_file_module.regs_update[31])
);
`endif

endmodule
