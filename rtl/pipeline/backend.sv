`include "common.svh"
`include "decoder.svh"

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
	// output bpu_update_t bpu_feedback_o,

    // 特权控制信号
    input priv_resp_t priv_resp_i,
    output priv_req_t priv_req_o,

	// 访存总线
    output cache_bus_req_t req_o,       // cache的访问请求
    input cache_bus_resp_t resp_i        // cache的访问应答


);

	// 信号定义
	// 后端暂停和清零向量
	logic [1:0][2:0] stall_vec, clr_vec;
	// 前端清零向量
	logic clr_frontend;

	// 发射向量
	logic [1:0] issue;
	logic revert;

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
		.stall_i(stall_vec[0][0] | stall_vec[0][1]) // 当 EX暂停时，不可以发射
	);

	// 生成前端使用的 issue_num 信号
	assign issue_num_o = {issue[1],issue[0] & ~issue[1]};

	// Register Files module, get the operation num


	/*
		Pipeline Registers here.
	*/

	// Excute 部分，对计算和跳转指令进行执行，对访存地址进行计算并完成第一阶段TLB比较 
	// ALU here

	// BPF here

	// AGU here

	// Mem 1 部分，准备读取Tag和Data的地址，进行TLB第二阶段比较。 （转发源）
	// Mem connection here

	// Mem 2 部分，TLB结果返回paddr，比较Tag，产生结果，对CSR堆进行控制。 
	// Mem connection here

	// CSR connection here

	// WB部分，选择写回源进行写回。（转发源）


endmodule