// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : bpu.sv
// Create : 2023-01-07 22:13:44
// Revise : 2023-02-21 17:06:49
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

`include "common.svh"
`include "bpu.svh"

module bpu (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input stall_i,
	input bpu_update_t update_front_i,
	input bpu_update_t update_back_i,
	output bpu_predict_t predict_o,
	output [31:0] pc_o,
	output [1:0] pc_valid_o,
	output stall_o
);
	// ================== merge ========================
	bpu_update_t update_i;
	always_comb begin
		if (update_back_i.flush) begin
			update_i = update_back_i;
		end else if (update_front_i.flush) begin
			update_i = update_front_i;
		end else begin
			update_i = update_back_i;
		end
	end
	// =================================================

	reg [31:0] pc;
	reg bpu_state;
	wire [31:2] npc;
	wire [31:2] ppc;
	wire fsc;

	// ==================== PC CTRL ====================

	localparam BPU_REFILL = 1'b0;
	localparam BPU_READY = 1'b1;

	// when flush, we need 1 clk to refill bpu pipe
	always_ff @(posedge clk) begin : proc_bpu_state
		if(~rst_n || update_i.flush) begin
			bpu_state <= BPU_REFILL;
		end else begin
			bpu_state <= BPU_READY;
		end
	end

	always_ff @(posedge clk) begin : proc_pc
		if(~rst_n) begin
			pc <= 32'h1c00_0000;
		end else if (update_i.flush) begin
			pc <= update_i.br_target;
		end else if (stall_i) begin
			pc <= pc;
		end else begin
			pc <= {npc, 2'b00};
		end
	end

	assign npc = bpu_state == BPU_REFILL | stall_i ? pc[31:2] : ppc;
	// ====================== BTB ======================
	wire [1:0] btb_br_type[1:0];
	wire [31:2] btb_bta[1:0];

	btb #(
		.ADDR_WIDTH(`_BTB_ADDR_WIDTH)
	) inst_btb (
		.clk       (clk),
		.rst_n     (rst_n),
		.rpc_i     (npc),
		.update_i  (update_i.btb_update),
		.wpc_i     (update_i.pc),
		.bta_i     (update_i.br_target[31:2]),
		.Br_type_i (update_i.br_type),
		.bta_o     (btb_bta),
		.Br_type_o (btb_br_type)
	);


	// ====================== LPHT =====================
	wire [1:0] lphr [1:0];

	pht #(
		.ADDR_WIDTH(`_LPHT_ADDR_WIDTH)
	) lpht_bank0 (
		.clk      (clk),
		.rst_n    (rst_n),
		.we_i     (update_i.lpht_update & ~update_i.lphr_index[0]),
		.taken_i  (update_i.br_taken),
		.phr_i    (update_i.lphr),
		.rindex_i (npc[`_LPHT_ADDR_WIDTH + 2:3]),
		.windex_i (update_i.lphr_index[`_LPHT_ADDR_WIDTH:1]),
		.phr_o    (lphr[0])
	);

	pht #(
		.ADDR_WIDTH(`_LPHT_ADDR_WIDTH)
	) lpht_bank1 (
		.clk      (clk),
		.rst_n    (rst_n),
		.we_i     (update_i.lpht_update & update_i.lphr_index[0]),
		.taken_i  (update_i.br_taken),
		.phr_i    (update_i.lphr),
		.rindex_i (npc[`_LPHT_ADDR_WIDTH + 2:3]),
		.windex_i (update_i.lphr_index[`_LPHT_ADDR_WIDTH:1]),
		.phr_o    (lphr[1])
	);

	// ====================== RAS ======================
	wire [31:2] ras_target;
	wire [$clog2(`_RAS_STACK_DEPTH) - 1:0] ras_ptr;

	ras #(
		.STACK_DEPTH(`_RAS_STACK_DEPTH)
	) inst_ras (
		.clk      (clk),
		.rst_n    (rst_n),
		.pop_i    (btb_br_type[fsc] == `_RETURN && ~stall_i),
		.push_i   (btb_br_type[fsc] == `_CALL && ~stall_i),
		.redirect_i (update_i.ras_redirect),
		.stack_ptr_i(update_i.ras_ptr),
		.target_i ({pc[30:3], 1'b0} + 30'd1 + fsc),
		.redirect_target_i(update_i.pc + 30'd1),
		.target_o (ras_target),
		.stack_ptr_o(ras_ptr)
	);

	// ================= predict logic =================
	wire taken0 = ((|btb_br_type[0]) | lphr[0][1]) & ~pc[2];
	wire taken1 = (|btb_br_type[1]) | lphr[1][1];
	assign fsc = (taken0 ? '0 : taken1) | pc[2];
	wire taken = taken0 | taken1;
	assign ppc = btb_br_type[fsc] == `_RETURN ? ras_target :
				 taken ? btb_bta[fsc] : {pc[31:3] + 29'd1, 1'b0};

	// output
	assign pc_o = pc;

	assign stall_o = bpu_state == BPU_REFILL;

	assign pc_valid_o[0] = ~pc[2] & rst_n & ~stall_o & ~stall_i; // pc是2字对齐的
	assign pc_valid_o[1] = (~taken0 | pc[2]) & rst_n & ~stall_o & ~stall_i; // 预测第一条不跳转或第一条无效

	assign predict_o.fsc = fsc;
	assign predict_o.taken = taken;
	assign predict_o.npc = npc;
	assign predict_o.lphr = lphr[fsc];
	assign predict_o.ras_ptr = ras_ptr;
	assign predict_o.br_type = btb_br_type[fsc];

	// debug
	wire[31:0] npc_32 = {npc, 2'b00};
	wire[31:0] src_32 = {update_i.pc, 2'b00};
endmodule : bpu


