// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : bpf.sv
// Create : 2023-01-11 14:38:56
// Revise : 2023-01-11 14:38:56
// Editor : sublime text4, tab size (4)
// Brief  : branch predicter feedback
// -----------------------------------------------------------------------------

`include "bpu.svh"
`include "../decoder/decoder.svh"

module bpf (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input [31:0] pc_i,
	input [25:0] offs_i,
	input [31:0] rj_i,
	input [31:0] rd_i,
	input [4:0] rj_index_i,
	input [4:0] rd_index_i,
	input reg_type_t reg_type_i,
	input cmp_type_t cmp_type_i,
	input branch_type_t br_type_i,
	input bpu_predict_t predict_i,
	output bpu_update_t update_o,
	output [31:0] target_o
);
	
	wire [31:0] offs_26 = {{6{offs_i[25]}}, offs_i};
	wire [31:0] offs_16 = {{16{offs_i[25]}}, offs_i[25:10]};

	assign target_o = br_type_i == `_BRANCH_IMMEDIATE ? pc_i + (offs_26 << 2) :
					  br_type_i == `_BRANCH_INDIRECT  ? rj_i + (offs_16 << 2) :
					  br_type_i == `_BRANCH_CONDITION ? pc_i + (offs_16 << 2) :
								   						pc_i + 4;
	
	logic taken;
	always_comb begin : proc_taken
		if (br_type_i == `_BRANCH_CONDITION) begin
			case (cmp_type_i)
				`_CMP_EQL: taken = rj_i == rd_i;
				`_CMP_NEQ: taken = rj_i != rd_i;
				`_CMP_LSS: taken = $signed(rj_i) < $signed(rd_i);
				`_CMP_GER: taken = $signed(rj_i) > $signed(rd_i);
				`_CMP_LEQ: taken = $signed(rj_i) <= $signed(rd_i);
				`_CMP_GEQ: taken = $signed(rj_i) >= $signed(rd_i);
				`_CMP_LTU: taken = rj_i < rd_i;
				`_CMP_GEU: taken = rj_i > rd_i;
				default : taken = 1'b0;
			endcase
		end else if (br_type_i != `_BRANCH_INVALID) begin
			taken = 1'b1;
		end else begin
			taken = 1'b0;
		end
	end

	// bpu update info
	assign update_o.flush = predict_i.npc != target_o[31:2];
	assign update_o.br_taken = taken;
	assign update_o.pc = pc_i[31:2];
	assign update_o.br_target = target_o[31:2];

	assign update_o.btb_update = update_o.flush;
	always_comb begin : proc_br_type
		if ((br_type_i == `_BRANCH_INDIRECT && rd_index_i == 1) || reg_type_i == `_REG_TYPE_BL) begin
			update_o.br_type = `_CALL;
		end else if (br_type_i == `_BRANCH_INDIRECT && rj_index_i == 1 && offs_16 == 0) begin
			update_o.br_type = `_RETURN;
		end else if (br_type_i == `_BRANCH_IMMEDIATE || br_type_i == `_BRANCH_INDIRECT) begin
			update_o.br_type = `_ABSOLUTE;
		end else begin
			update_o.br_type = `_PC_RELATIVE;
		end
	end

	assign update_o.bht_update = 1'b1;

	assign update_o.lpht_update = 1'b1;
	assign update_o.lphr = predict_i.lphr;
	assign update_o.lphr_index = predict_i.lphr_index;
endmodule : bpf

