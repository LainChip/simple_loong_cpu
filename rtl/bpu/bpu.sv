// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : bpu.sv
// Create : 2023-01-07 22:13:44
// Revise : 2023-01-15 09:10:26
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

`include "bpu.svh"

module bpu (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input stall_i,
	input bpu_update_t update_i,
	output bpu_predict_t predict_o,
	output reg [31:0] pc_o,
	output stall_o
);

	initial begin
    	$dumpfile("logs/vlt_dump.vcd");
    	$dumpvars();
	end

	reg [31:2] pc;
	reg bpu_state;
	wire [31:2] npc;
	wire [31:2] ppc;

	// ==================== PC CTRL ====================

	localparam BPU_REFILL = 1'b0;
	localparam BPU_READY = 1'b1;

	// when flush, we need 1 clk to refill bpu pipe
	always_ff @(posedge clk or negedge rst_n) begin : proc_bpu_state
		if(~rst_n || update_i.flush) begin
			bpu_state <= BPU_REFILL;
		end else begin
			bpu_state <= BPU_READY;
		end
	end

	always_ff @(posedge clk or negedge rst_n) begin : proc_pc
		if(~rst_n) begin
			pc <= 30'h0700_0000; // 32'h1c00_0000
		end else if (update_i.flush) begin
			pc <= update_i.br_target;
		end else if (stall_i) begin
			pc <= pc;
		end else begin
			pc <= npc;
		end
	end

	assign npc = bpu_state == BPU_REFILL ? pc : ppc;

	// ====================== BTB ======================
	wire btb_miss;
	wire btb_fsc;
	wire [1:0] btb_br_type;
	wire [31:2] btb_bta;

	btb #(
		.ADDR_WIDTH(`_BTB_ADDR_WIDTH)
	) inst_btb (
		.clk       (clk),
		.rst_n     (rst_n),
		.rpc_i     (npc),
		.update_i  (update_i.btb_update),
		.wpc_i     (update_i.pc),
		.bta_i     (update_i.br_target),
		.Br_type_i (update_i.br_type),
		.fsc_o     (btb_fsc),
		.miss_o    (btb_miss),
		.bta_o     (btb_bta),
		.Br_type_o (btb_br_type)
	);


	// ====================== LPHT =====================
	wire [1:0] lphr;

	pht #(
		.ADDR_WIDTH(`_LPHT_ADDR_WIDTH)
	) lpht (
		.clk      (clk),
		.rst_n    (rst_n),
		.we_i     (update_i.lpht_update),
		.taken_i  (update_i.br_taken),
		.phr_i    (update_i.lphr),
		.rindex_i (npc[`_LPHT_ADDR_WIDTH - 1:0]),
		.windex_i (update_i.lphr_index),
		.phr_o    (lphr)
	);

	// ====================== RAS ======================
	wire [31:2] ras_target;

	ras #(
		.STACK_DEPTH(`_RAS_STACK_DEPTH)
	) inst_ras (
		.clk      (clk),
		.rst_n    (rst_n),
		.pop_i    (btb_br_type == `_RETURN && ~stall_i),
		.push_i   (btb_br_type == `_CALL && ~stall_i),
		.target_i (npc + 4),
		.target_o (ras_target)
	);

	// ================= predict logic =================
	// taken = btb_br_type != `_PC_RELATIVE | lphr == `_STRONGLY_TAKEN | lphr == `_WEAKLY_TAKEN
	wire taken = |btb_br_type | lphr[1];
	assign ppc = btb_br_type == `_RETURN ? ras_target :
				 taken ? btb_bta : {pc[31:3] + 29'd1, 1'b0};

	assign predict_o.fsc = btb_fsc;
	assign predict_o.npc = npc;
	assign predict_o.lphr = lphr;
	assign predict_o.lphr_index = pc[`_LPHT_ADDR_WIDTH - 1:0];

endmodule : bpu


