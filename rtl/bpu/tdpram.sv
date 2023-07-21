// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : tdpram.sv
// Create : 2023-01-24 10:35:16
// Revise : 2023-01-24 10:35:16
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

/*--JSON--{"module_name":"deperated","module_ver":"3","module_type":"module"}--JSON--*/
module tdpram #(
  	parameter DATA_WIDTH = 8,
  	parameter ADDR_WIDTH = 4
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	input ena,
	input enb,
	input wea,
	input web,
	input [ADDR_WIDTH - 1:0] addra,
	input [ADDR_WIDTH - 1:0] addrb,
	input [DATA_WIDTH - 1:0] dina,
	input [DATA_WIDTH - 1:0] dinb,
	output reg [DATA_WIDTH - 1:0] douta,
	output reg [DATA_WIDTH - 1:0] doutb
);

	parameter RAM_DEPTH = 1 << ADDR_WIDTH;
	reg [DATA_WIDTH - 1:0] ram [0:RAM_DEPTH - 1];

	always @ (posedge clk) begin
		if (ena & wea & rst_n) begin
			ram[addra] <= dina;
		end

		if (enb & web & rst_n) begin
			ram[addrb] <= dinb;
		end

		if (~rst_n) begin
			douta <= {DATA_WIDTH{1'b0}};
		end else if (ena) begin
			douta <= ram[addra];
		end else begin
			douta <= {DATA_WIDTH{1'b0}};
		end

		if (~rst_n) begin
			doutb <= {DATA_WIDTH{1'b0}};
		end else if (enb) begin
			doutb <= ram[addrb];
		end else begin
			doutb <= {DATA_WIDTH{1'b0}};
		end
	end


endmodule : tdpram

