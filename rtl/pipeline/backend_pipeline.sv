`include "common.svh"
`include "decoder.svh"
`include "pipeline.svh"

module backend_pipeline #(
	parameter bit MAIN_PIPE = 1'b1
)(
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low

	// 控制用暂停信号
	input logic [2:0] stall_vec_i, // 0 for ex, 1 for m1, 2 for m2
	input logic [2:0] clr_vec_i,   // 0 for ex, 1 for m1, 2 for m2

	// 暂停请求
	output logic ex_stall_req_o,
	output logic m1_stall_req_o,
	output logic m2_stall_req_o,

	input logic revert_i,
	ctrl_flow_t ctrl_flow_i,
	data_flow_t data_flow_i,

	// FORWARDING DATA SOURCE
	input logic[1:0][2:0][31:0] forwarding_src_i,

	// FORWARDING DATA OUTPUT
	output logic[2:0] forwarding_data_o,

	output logic[4:0]  reg_w_addr_o,
	output logic[31:0] reg_w_data_o,
	
	// FOR MAIN PIPE
	output cache_bus_req_t req_o,       // cache的访问请求
    input cache_bus_resp_t resp_i        // cache的访问应答
    input priv_resp_t priv_resp_i,
    output priv_req_t priv_req_o,
    output bpu_update_t bpu_feedback_o,

);

endmodule : backend_pipeline