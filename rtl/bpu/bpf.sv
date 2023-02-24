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
`include "decoder.svh"

module bpf (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input csr_flush_i,
	input stall_i,
	input [31:0] pc_i,
	input [31:0] rj_i,
	input [31:0] rd_i,
	input [31:0] csr_target_i,
	input decode_info_t decode_i,
	input bpu_predict_t predict_i,
	output bpu_update_t update_o,
	output [31:0] pc_link_o
);

	logic taken;

	wire [25:0] offs_i = decode_i.general.inst25_0; 
	wire [4:0] rj_index_i = decode_i.general.inst25_0[9:5];
	wire [4:0] rd_index_i = decode_i.general.inst25_0[4:0];
	cmp_type_t cmp_type_i;
	assign cmp_type_i = decode_i.ex.cmp_type;
	branch_type_t branch_type_i = decode_i.ex.branch_type;
	
	wire [31:0] offs_26 = {{4{offs_i[9]}},offs_i[9:0], offs_i[25:10], 2'b00};
	wire [31:0] offs_16 = {{14{offs_i[25]}}, offs_i[25:10], 2'b00};

	(* mark_debug="true" *) wire [31:0] target = (branch_type_i == `_BRANCH_IMMEDIATE) 		    ? (pc_i + (offs_26)) :(
					     						 (branch_type_i == `_BRANCH_INDIRECT)  		    ? (rj_i + (offs_16)) :(
					     						 (branch_type_i == `_BRANCH_CONDITION && taken) ? (pc_i + (offs_16)) :(
								   						       			// pc_i + 4;
								   						       			{pc_i[31:3] + 29'd1, 3'b000})));

	wire predict_taken = predict_i.fsc == pc_i[2] ? predict_i.taken : 1'b0;
	wire [31:0] predict_npc = {predict_i.npc, 2'b00};
	
	
	always_comb begin : proc_taken
		if (branch_type_i == `_BRANCH_CONDITION) begin
			case (cmp_type_i)
				`_CMP_EQL: taken = rj_i == rd_i;
				`_CMP_NEQ: taken = rj_i != rd_i;
				`_CMP_LSS: taken = $signed(rj_i) < $signed(rd_i);
				`_CMP_GER: taken = $signed(rj_i) > $signed(rd_i);
				`_CMP_LEQ: taken = $signed(rj_i) <= $signed(rd_i);
				`_CMP_GEQ: taken = $signed(rj_i) >= $signed(rd_i);
				`_CMP_LTU: taken = rj_i < rd_i;
				`_CMP_GEU: taken = rj_i >= rd_i;
				default : taken = 1'b0;
			endcase
		end else if (branch_type_i != `_BRANCH_INVALID) begin
			taken = 1'b1;
		end else begin
			taken = 1'b0;
		end
	end

	// link
	assign pc_link_o = pc_i + 4;

	// bpu update
	// 添加taken的判断，因为有分支指令的目标为pc+8，如果bpu未预测到则pc+4的指令会被标记为有效
	// 需要在此处检查这样的预测错误
	wire target_miss = predict_npc != target;
	wire direction_miss = predict_taken != taken;
	wire predict_miss = (target_miss & predict_i.taken) | direction_miss;
	assign update_o.flush = (~stall_i & predict_miss & decode_i.wb.valid) | csr_flush_i;
	assign update_o.br_taken = taken;
	assign update_o.pc = pc_i[31:2];
	// 如果第一条(pc[2] == 0)指令被误判为跳转，修复的目标为pc+4
	assign update_o.br_target = csr_flush_i ? csr_target_i[31:0] : 
								(pc_i[2] == '0 && taken == '0 && predict_i.taken == '1) ? {pc_i[31:2] + 30'd1, 2'b00} : 
								target[31:0];

	assign update_o.btb_update = 1'b1;
	always_comb begin : proc_br_type
		if ((branch_type_i == `_BRANCH_INDIRECT && rd_index_i == 1) || decode_i.ex.branch_link) begin
			update_o.br_type = `_CALL;
		end else if (branch_type_i == `_BRANCH_INDIRECT && rj_index_i == 1 && offs_16 == 0) begin
			update_o.br_type = `_RETURN;
		end else if (branch_type_i == `_BRANCH_IMMEDIATE || branch_type_i == `_BRANCH_INDIRECT) begin
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

