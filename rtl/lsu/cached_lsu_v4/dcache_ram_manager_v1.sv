`include "cached_lsu_v4.svh"

module lsu_dm#(
    parameter int PIPE_MANAGE_NUM = 2,
    parameter int BANK_NUM = 2 // FIXED ACTUALLY.
)(
    input logic clk,
    input logic rst_n,

    input dram_manager_req_t[PIPE_MANAGE_NUM - 1:0] dm_req_o,
    output dram_manager_resp_t[PIPE_MANAGE_NUM - 1:0] dm_resp_i,
    output dram_manager_snoop_t dm_snoop_i
);
endmodule