`timescale 1ns / 1ps

`include "types.svh"
`include "issue.svh"

module dual_fifo #(
    parameter int DEPTH = 4,
    parameter int DATA_SIZE = 32
) (
    input clk,   // Clock`
    input rst_n, // Asynchronous reset active low

    // 控制信号
    input [1:0]push_i,
    input [1:0]pop_i,
    output [1:0]valid_o,
    output full_o,

    // 数据信号
    input [1:0][DATA_SIZE - 1 : 0] data_i,
    output [1:0][DATA_SIZE - 1 : 0] data_o
);

endmodule
