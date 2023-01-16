`include "common.svh"
`include "decoder.svh"
`include "pipeline.svh"

module backend(
	input clk,
	input rst_n,

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
	logic [1:0][2:0] stall_vec, clr_vec, stall_req, clr_req;
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

	// ISSUE 部分，对指令进行发射
	// Issue module, judge whether we can issue or not
	issue issue_module(
		.inst_i(inst_i),
		.inst_valid_i(inst_valid_i),
		.stall_vec_i(stall_vec),			// 0 for ex, 1 for m1, 2 for m2
		.clr_vec_i(clr_vec),				// 0 for ex, 1 for m1, 2 for m2
		.clr_frontend_i(clr_frontend),

		.issue_o(issue), // 2'b00, 2'b01, 2'b11 三种情况，指令必须顺序发射.
		.revert_o(revert),         // send inst[0] to pipe[1], inst[1] to pipe[0]. otherwise, inst[0] to pipe[0], inst[1] to pipe[1]
		.forwarding_info_o(forwarding_info)

		.stall_i(stall_vec[0][0] | stall_vec[0][1]) // 当 EX暂停时，不可以发射
	);

	// 生成前端使用的 issue_num 信号
	assign issue_num_o = {issue[1],issue[0] & ~issue[1]};

	// Register Files module, get the operation num
	reg_file #(
		.DATA_WIDTH          (32)，
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
		inst_t inst_sel = inst_i[revert ^ pipe_id];
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

	.revert_vector_o(revert_vector),
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

	.revert_vector_o(/* revert vector */),
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
			clr_vec[0][level] |= clr_req[0][level];
			clr_vec[1][level] |= clr_req[0][level] & revert_vector[level];
		end
	end

endmodule