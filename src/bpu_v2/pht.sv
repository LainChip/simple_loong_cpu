// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : pht.sv
// Create : 2023-01-31 19:02:40
// Revise : 2023-01-31 19:09:51
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------


`include "include/bpu.svh"

module pht #(
	parameter ADDR_WIDTH = 10
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input we_i,
    input taken_i,
    input [1:0] phr_i,
    input [ADDR_WIDTH - 1:0] rindex_i,
    input [ADDR_WIDTH - 1:0] windex_i,
    output [1:0] phr_o
);

	wire [1:0] wdata = 
            phr_i == 2'b11 ? (taken_i ? 2'b11 : 2'b10) :
            phr_i == 2'b10 ? (taken_i ? 2'b11 : 2'b01) :
            phr_i == 2'b01 ? (taken_i ? 2'b10 : 2'b00) :
                             (taken_i ? 2'b01 : 2'b00);

	sdpram #(
		.DATA_WIDTH(2),
		.ADDR_WIDTH(ADDR_WIDTH)
	) inst_sdpram (
		.clk     (clk),
		.rst_n   (rst_n),
		.en_i    (1'b1),
		.we_i    (we_i),
		.raddr_i (rindex_i),
		.waddr_i (windex_i),
		.din_i   (wdata),
		.dout_o  (phr_o)
	);


endmodule : pht
