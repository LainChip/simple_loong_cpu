// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : bht.sv
// Create : 2023-02-02 10:43:38
// Revise : 2023-02-02 10:54:33
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

`include "include/bpu.svh"

module bht #(
    parameter ADDR_WIDTH = 5,
    parameter DATA_WIDTH = 3,
    parameter BLOCK_SIZE = 2
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	input  we_i,
    input  [31:0] rpc_i,
    input  [31:0] wpc_i,
    input  [DATA_WIDTH - 1:0] bhr_i,
    input  taken_i,
    output [DATA_WIDTH - 1:0] bhr_o
);

	localparam OFFSET_BLOCK_SIZE = $clog2(BLOCK_SIZE) + 2;

    wire  [ADDR_WIDTH - 1:0] raddr = rpc_i[ADDR_WIDTH + OFFSET_BLOCK_SIZE - 1:OFFSET_BLOCK_SIZE];
    wire  [ADDR_WIDTH - 1:0] waddr = wpc_i[ADDR_WIDTH + OFFSET_BLOCK_SIZE - 1:OFFSET_BLOCK_SIZE];

    logic [(1 << ADDR_WIDTH) - 1 : 0][DATA_WIDTH - 1:0] bht_mem;

    // read
    assign bhr_o = rst_n ? bht_mem[raddr] : 0;

    // write
    always @(posedge clk ) begin
        if (we_i) begin
            bht_mem[waddr] <=  {bhr_i[DATA_WIDTH - 2:0], taken_i};
        end 
    end

endmodule : bht