`include "common.svh"
`include "decoder.svh"

module backend(
	input clk,
	input rst_n,

	// 调试用输出信号组
	output debug_info_t debug_info_o,

	// 指令输入
	input decode_info_t [1:0] decode_info_i,

	// BPU 输入（随指令走）
	input bpu_predict_t [1:0] bpu_predict_i,
	output bpu_update_t bpu_feedback_o,

    // 特权控制信号
    input priv_resp_t priv_resp_i,
    output priv_req_t priv_req_o,

	// 访存总线
    output cache_bus_req_t req_o,       // cache的访问请求
    input cache_bus_resp_t resp_i        // cache的访问应答


);

	// ISSUE 部分，对指令进行发射

	// Excute 部分，对计算和跳转指令进行执行，对访存地址进行计算并完成第一阶段TLB比较 

	// Mem 1 部分，准备读取Tag和Data的地址，进行TLB第二阶段比较。 （转发源）

	// Mem 2 部分，TLB结果返回paddr，比较Tag，产生结果，对CSR堆进行控制。 

	// WB部分，选择写回源进行写回。（转发源）


endmodule