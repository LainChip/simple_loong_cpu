// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : npc.sv
// Create : 2023-01-07 20:49:15
// Revise : 2023-01-07 21:52:08
// Editor : sublime text4, tab size (4)
// -----------------------------------------------------------------------------

module npc (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input stall,  // stall active high
	input taken,  // branch or not active high
	input [31:0] target, // branch target
	output reg [31:0] pc // inst addr
);

	always_ff @(posedge clk or negedge rst_n) begin : proc_pc
		if(~rst_n) begin
			pc <= 32'h1c000000;
		end else begin
			if (taken) begin
				pc <= target;
			end
			else if (stall) begin
				pc <= pc;
			end
			else begin
				pc <= pc + 8;
			end
		end
	end

	
endmodule : npc