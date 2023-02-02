// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : npc.sv
// Create : 2023-01-30 17:35:56
// Revise : 2023-01-30 17:42:27
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

`include "include/bpu.svh"

module npc (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input stall_i,
	input bpu_update_t update_i,
	output stall_o,
	output reg [31:0] pc_o,
	output bpu_predict_t predict_o
);

	wire flush = update_i.flush;
	wire [31:0] target = {update_i.br_target, 2'b00};
	wire [31:0] npc = {pc_o[31:3] + 1, 3'b000};

	always_ff @(posedge clk or negedge rst_n) begin : proc_pc
		if(~rst_n) begin
			pc_o <= 32'h1c00_0000;
		end else begin
			if (flush) begin
				pc_o <= target;
			end
			else if (stall_i) begin
				pc_o <= pc_o;
			end
			else begin
				pc_o <= npc;
			end
		end
	end

	assign stall_o = 1'b0;
	assign predict_o.taken = 1'b0;
	assign predict_o.npc = npc;

endmodule : npc