// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : tdpram.sv
// Create : 2023-01-24 10:35:16
// Revise : 2023-01-31 16:09:31
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

module tdpram #(
  	parameter DATA_WIDTH = 8,
  	parameter ADDR_WIDTH = 4
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	input ena_i,
	input enb_i,
	input wea_i,
	input web_i,
	input [ADDR_WIDTH - 1:0] addra_i,
	input [ADDR_WIDTH - 1:0] addrb_i,
	input [DATA_WIDTH - 1:0] dina_i,
	input [DATA_WIDTH - 1:0] dinb_i,
	output reg [DATA_WIDTH - 1:0] douta_o,
	output reg [DATA_WIDTH - 1:0] doutb_o
);

	parameter RAM_DEPTH = 1 << ADDR_WIDTH;
	reg [DATA_WIDTH - 1:0] ram [0:RAM_DEPTH - 1];

	always @ (posedge clk) begin
		if (ena_i & wea_i & rst_n) begin
			ram[addra_i] <= dina_i;
		end

		if (enb_i & web_i & rst_n) begin
			ram[addrb_i] <= dinb_i;
		end

		if (~rst_n) begin
			douta_o <= {DATA_WIDTH{1'b0}};
		end else if (ena_i) begin
			douta_o <= ram[addra_i];
		end else begin
			douta_o <= {DATA_WIDTH{1'b0}};
		end

		if (~rst_n) begin
			doutb_o <= {DATA_WIDTH{1'b0}};
		end else if (enb_i) begin
			doutb_o <= ram[addrb_i];
		end else begin
			doutb_o <= {DATA_WIDTH{1'b0}};
		end
	end


endmodule : tdpram

