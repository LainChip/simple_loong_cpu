/*--JSON--{"module_name":"lsu","module_ver":"3","module_type":"module"}--JSON--*/

module lsu (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	// 控制信号
	input decode_info_t  ex_decode_info_i, // EX STAGE

    input logic ex_valid,   // 表示指令在 ex 级是有效的

    input logic m1_valid,   // 表示指令在 m1 级是有效的
    input logic m1_taken,   // 表示指令在 m1 级接受了后续指令
    output logic m1_busy_o, // 表示 cache 在 m1 级的处理被阻塞

    input logic m2_valid,   // 表示指令在 m1 级是有效的
    input logic m2_taken,   // 表示指令在 m2 级的处理已完成，可以接受后续指令
    output logic m2_busy_o, // 表示 cache 在 m2 级的处理被阻塞

	// 流水线数据输入输出
	input  logic[31:0] ex_vaddr_i,   // EX STAGE
	input  logic[31:0] m1_paddr_i,   // M1 STAGE
    output logic[31:0] m1_rdata_o, 
    output logic       m1_rvalid_o,

	input logic[31:0]  m2_wdata_i,  // M2 STAGE
    input logic        m2_uncached_i,
    output logic[31:0] m2_rdata_o, 
    output logic       m2_rvalid_o,

	output logic[31:0] m2_vaddr_o,
	output logic[31:0] m2_paddr_o,

    // 连接一致性总线
    input coherence_bus_req_t creq_i,
    output coherence_bus_resp_t cresp_o,

	// 连接内存总线
	output cache_bus_req_t breq_o,
	input cache_bus_resp_t bresp_i,

	// 握手信号
	output logic busy_o,
	input stall_i
);

    // RAM 控制读写握手信号
    logic cm_tag_w_req,rm_tag_req; // 由 RM 去处理写时 DIRTY 非1 的情况
    logic cm_tag_w_gnt,rm_tag_gnt; // 由 RM 去处理写时 DIRTY 非1 的情况

    logic cm_data_r_req,rm_data_r_req,pm_data_r_req;
    logic cm_data_r_gnt,rm_data_r_gnt,pm_data_r_gnt;
    logic cm_data_w_req,cm_data_w_req,pm_data_w_req;
    logic cm_data_w_gnt,cm_data_w_gnt,pm_data_w_gnt;

    // 对于

    // ADDRESS TAG RAM 模块，3r1w

    // VALID RAM 3r1w

    // UNIQUE RAM 3r1w

    // DIRTY RAM 3r1w

    // DATA RAM 模块

    // 三个控制层，优先级递减，优先供给 Coherent Manage 和 Refill Manage 使用
    // Coherent Manage

    // Refill Manage

    // Pipeline Manage

endmodule