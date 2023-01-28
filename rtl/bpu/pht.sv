// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : pht.sv
// Create : 2023-01-08 19:04:04
// Revise : 2023-01-08 19:13:22
// Editor : sublime text4, tab size (4)
// -----------------------------------------------------------------------------

`include "bpu.svh"

module pht #(
	parameter ADDR_WIDTH = 8
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
        .ADDR_WIDTH ( ADDR_WIDTH    ),
        .DATA_WIDTH ( 2             )
    ) u_sdpram (
        .clk                     ( clk     ),
        .rst_n                   ( rst_n   ),
        .en                      ( 1'b1    ),
        .we                      ( we_i    ),
        .raddr                  ( rindex_i ),
        .waddr                  ( windex_i ),
        .wdata                   ( wdata   ),
        .rdata                   ( phr_o   )
    );

endmodule : pht
