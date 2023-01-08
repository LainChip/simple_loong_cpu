// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : npc.sv
// Create : 2023-01-07 20:49:15
// Revise : 2023-01-08 17:07:09
// Editor : sublime text4, tab size (4)
// -----------------------------------------------------------------------------

module npc (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input stall_i,
	input bpu_update_info_t update_i,
	output bpu_predict_info_t bpinfo_o,
	output reg [31:0] pc_o,
	output stall_o
);

	always_ff @(posedge clk or negedge rst_n) begin : proc_pc
		if(~rst_n) begin
			pc_o <= 32'h1c00_0000;
		end else begin
			if (taken) begin
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
	assign bpinfo_o.npc = npc;

	
endmodule : npc

`endif // __NPC_VER_1
