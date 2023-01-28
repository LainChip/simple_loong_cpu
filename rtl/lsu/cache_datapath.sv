`include "common.svh"

module cache_data_path#(
    parameter int PAGE_SHIFT_LEN = 12,
    parameter int WORD_INDEX_LEN = 7,
    parameter int LANE_SHIFT_LEN = 3,
    parameter int WORD_SHIFT_LEN = 2,
    parameter int WAY_CNT = 4 
)(
    input clk,
    input rst_n,
    // 一个读口
    input logic[PAGE_SHIFT_LEN - 1 : WORD_SHIFT_LEN] r_addr_i,
    output logic[WAY_CNT - 1 : 0][(8 << WORD_SHIFT_LEN) - 1 : 0] r_data_o

    // 一个写口，读写需要转发
    input logic[PAGE_SHIFT_LEN - 1 : WORD_SHIFT_LEN] w_addr_i,
    input logic[WAY_CNT - 1 : 0] we_i,
    input logic[(8 << WORD_SHIFT_LEN) - 1 : 0] w_data_i
);

    

endmodule