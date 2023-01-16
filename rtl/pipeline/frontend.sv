`include "common.svh"
`include "decoder.svh"
`include "pipeline.svh"

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

    logic frontend_stall,frontend_clr;
    bpu_predict_t bpu_predict;

    // NPC / BPU 模块
    module npc (
        input clk,    // Clock
        input rst_n,  // Asynchronous reset active low
        input stall_i,
        input bpu_update_t update_i,
        output bpu_predict_t predict_o,
        output reg [31:0] pc_o,
        output stall_o
    );
    npc(
        .clk,
        .rst_n,
        .stall_i(frontend_stall),
        .update_i(bpu_feedback_i),
        .predict_o(bpu_predict),
        
    )

endmodule