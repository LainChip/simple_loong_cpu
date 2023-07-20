module ifetch#(
    parameter int ATTACHED_INFO_WIDTH = 32,     // 用于捆绑bpu输出的信息，跟随指令流水
    parameter int WAY_CNT = 2                  // 指示cache的组相联度
  )(
    input clk,    // Clock
    input rst_n,  // Asynchronous reset active low

    input  logic [1:0] cacheop_i, // 输入两位的cache控制信号
    input  logic cacheop_valid_i, // 输入的cache控制信号有效
    output logic cacheop_ready_o,

    input  logic [31:0]vpc_i,
    input  logic [1: 0] valid_i,
    input  logic [ATTACHED_INFO_WIDTH - 1 : 0] attached_i,

    // MMU 访问信号, 在 VPC 后一拍
    input 


    output logic [31:0]vpc_o,
    output logic [31:0]ppc_o,
    output logic [FETCH_SIZE - 1 : 0] valid_o,
    output logic [ATTACHED_INFO_WIDTH - 1 : 0] attached_o,
    output logic [FETCH_SIZE - 1 : 0][31:0] inst_o,
    (* mark_debug="true" *) output fetch_excp_t fetch_excp_o,
    // output decode_info_t [FETCH_SIZE - 1 : 0] decode_output_o,

    input  logic ready_i, // FROM QUEUE
    output logic ready_o, // TO NPC/BPU
    input  logic clr_i,

    input logic bus_busy_i,

    (* mark_debug="true" *) output cache_bus_req_t bus_req_o,
    (* mark_debug="true" *) input cache_bus_resp_t bus_resp_i,
    input uncached_i
    // input trans_en_i
  );
endmodule
