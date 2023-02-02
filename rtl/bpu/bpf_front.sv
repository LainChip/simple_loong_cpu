// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : bpf_front.sv
// Create : 2023-01-31 14:22:04
// Revise : 2023-01-31 14:57:40
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

`include "../decoder/decoder.svh"
`include "bpu.svh"

module bpf_front (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input [31:0] pc_i,
	input decode_info_t [0:1] decode_i,
	input bpu_predict_t predict_i,
	output bpu_update_t update_o,
	output bpu_predict_t predict_o
);

	assign update_o.flush = predict_i.taken &
							((predict_i.fsc == 1'b0 && decode_i[0].ex.branch_type == `_BRANCH_INVALID) |
							(predict_i.fsc == 1'b1 && decode_i[1].ex.branch_type == `_BRANCH_INVALID));
	assign update_o.pc = pc_i;
	assign update_o.br_target = {pc_i[31:3] + 1, 3'b000};
	assign update_o.lphr = predict_i.lphr;
	assign update_o.lphr_index = predict_i.lphr_index;
	assign update_o.br_taken = 1'b0;
	assign update_o.br_type = `_PC_RELATIVE;
	assign update_o.btb_update = update_o.flush;
	assign update_o.lpht_update = update_o.flush;
	assign update_o.bht_update = update_o.flush;


	always_comb begin
		predict_o = predict_i;
		if (update_o.flush) begin
			predict_o.taken = 1'b0;
			predict_o.npc = {pc_i[31:3] + 1, 3'b000};
		end
	end



endmodule : bpf_front
