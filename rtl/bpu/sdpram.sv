// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : sdpram.sv
// Create : 2023-01-24 17:26:20
// Revise : 2023-01-24 17:31:02
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

/*--JSON--{"module_name":"deperated","module_ver":"3","module_type":"module"}--JSON--*/
module sdpram #(
	parameter DATA_WIDTH = 8,
	parameter ADDR_WIDTH = 4
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input en,
	input we,
	input [ADDR_WIDTH - 1:0] raddr,
	input [ADDR_WIDTH - 1:0] waddr,
	input [DATA_WIDTH - 1:0] wdata,
	output reg [DATA_WIDTH - 1:0] rdata
);

	parameter RAM_DEPTH = 1 << ADDR_WIDTH;
	reg [DATA_WIDTH - 1:0] ram [0:RAM_DEPTH - 1];

	always @(posedge clk) begin
		if (en & we) begin
			ram[waddr] <= wdata;
		end

		if (~rst_n) begin
			rdata <= 0;
		end else if (en) begin
			rdata <= ram[raddr];
		end else begin
			rdata <= 0;
		end
	end

endmodule : sdpram