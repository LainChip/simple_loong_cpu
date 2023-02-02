// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : sdpram.sv
// Create : 2023-01-24 17:26:20
// Revise : 2023-01-31 19:04:27
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

module sdpram #(
	parameter DATA_WIDTH = 8,
	parameter ADDR_WIDTH = 4
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input en_i,
	input we_i,
	input [ADDR_WIDTH - 1:0] raddr_i,
	input [ADDR_WIDTH - 1:0] waddr_i,
	input [DATA_WIDTH - 1:0] din_i,
	output reg [DATA_WIDTH - 1:0] dout_o
);

	localparam RAM_DEPTH = 1 << ADDR_WIDTH;
	reg [DATA_WIDTH - 1:0] ram [0:RAM_DEPTH - 1];

	always @(posedge clk) begin
		if (en_i & we_i) begin
			ram[waddr_i] <= din_i;
		end

		if (~rst_n) begin
			dout_o <= 0;
		end else if (en_i) begin
			dout_o <= ram[raddr_i];
		end else begin
			dout_o <= 0;
		end
	end

endmodule : sdpram