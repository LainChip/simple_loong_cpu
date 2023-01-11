// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : bht.sv
// Create : 2023-01-10 10:20:48
// Revise : 2023-01-10 10:27:36
// Editor : sublime text4, tab size (4)
// -----------------------------------------------------------------------------

`include "bpu.svh"

module bht #(
	parameter ADDR_WIDTH = `_BHT_ADDR_WIDTH,
    parameter DATA_WIDTH = `_BHT_DATA_WIDTH
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input we,
    input [31:0] rpc,
    input [31:0] wpc,
    input br_taken,
    output [DATA_WIDTH - 1:0] bhr
);

	wire  [ADDR_WIDTH - 1:0] raddr = rpc[ADDR_WIDTH + 2:3];
    wire  [ADDR_WIDTH - 1:0] waddr = wpc[ADDR_WIDTH + 2:3];

    reg [DATA_WIDTH - 1:0] bht [1 << ADDR_WIDTH - 1:0];

    // read
    assign bhr = ~rst_n ? 32'h0000_0000 : bht[waddr];

    // write
    always @(posedge clk ) begin
        if (we) begin
            bht[waddr] <= (bht[waddr] << 1) | br_taken;
        end else begin
            bht[waddr] <= bht[waddr];
        end
    end

endmodule : bht