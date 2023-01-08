// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : npc.sv
// Create : 2023-01-07 20:49:15
// Revise : 2023-01-08 14:46:11
// Editor : sublime text4, tab size (4)
// -----------------------------------------------------------------------------

module npc (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input stall_i,  // stall active high
	input taken_i,  // branch or not active high
	input [31:0] target_i, // branch target
	output reg [31:0] pc_o // inst addr
);

	always_ff @(posedge clk or negedge rst_n) begin : proc_pc
		if(~rst_n) begin
			pc_o <= 32'h1c000000;
		end else begin
			if (taken_i) begin
				pc_o <= target_i;
			end
			else if (stall_i) begin
				pc_o <= pc_o;
			end
			else begin
				pc_o <= {pc_o[31:3] + 1, 3'b000};
			end
		end
	end

	
endmodule : npc