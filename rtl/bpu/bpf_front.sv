// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : bpf_front.sv
// Create : 2023-01-31 14:22:04
// Revise : 2023-02-18 19:39:34
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

`include "decoder.svh"
`include "bpu.svh"

module bpf_front (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input fifo_ready_i,
	input [31:0] pc0_i,
	input [31:0] pc1_i,
	input [1:0] valid_i,
	input decode_info_t [1:0] decode_i,
	input bpu_predict_t predict0_i,
	input bpu_predict_t predict1_i,
	output bpu_update_t update_o,
	output bpu_predict_t [1:0] predict_o,
	output [1:0] valid_o
);

	wire fst_miss = predict0_i.taken && predict0_i.fsc == pc0_i[2] && decode_i[0].ex.branch_type == `_BRANCH_INVALID && valid_i[0];
	wire sec_miss = predict1_i.taken && predict1_i.fsc == pc1_i[2] && decode_i[1].ex.branch_type == `_BRANCH_INVALID && valid_i[1];

	assign update_o.flush = (fst_miss | sec_miss) & fifo_ready_i;
	assign update_o.pc = fst_miss ? pc0_i[31:2] : pc1_i[31:2];
	assign update_o.br_target = fst_miss ? pc0_i + 4 : pc1_i + 4;
	assign update_o.lphr = fst_miss ? predict0_i.lphr : predict1_i;
	assign update_o.lphr_index = fst_miss ? predict0_i.lphr_index : predict1_i;
	assign update_o.br_taken = 1'b0;
	assign update_o.br_type = `_PC_RELATIVE;
	assign update_o.btb_update = update_o.flush;
	assign update_o.lpht_update = update_o.flush;
	assign update_o.bht_update = update_o.flush;


	always_comb begin
		predict_o[0] = predict0_i;
		predict_o[1] = predict1_i;
		if (fst_miss) begin
			predict_o[0].taken = 1'b0;
			predict_o[0].npc = {pc0_i[31:3] + 1, 3'b000};
		end

		if (sec_miss) begin
			predict_o[1].taken = 1'b0;
			predict_o[1].npc = {pc1_i[31:3] + 1, 3'b000};
		end
	end

	assign valid_o[0] = valid_i[0];
	assign valid_o[1] = valid_i[1] & ~fst_miss;



endmodule : bpf_front