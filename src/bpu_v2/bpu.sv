// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : bpu.sv
// Create : 2023-01-31 16:04:13
// Revise : 2023-02-02 11:08:32
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

`include "include/bpu.svh"

module bpu (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input stall_i,
	input bpu_update_t update_i,
	output stall_o,
	output [`_BLOCK_SIZE - 1:0] pc_valid_o,
	output [31:0] pc_o,
	output bpu_predict_t predict_o
);

	reg [31:0] pc;
	reg bpu_state;
	wire [31:2] npc, ppc;
	wire taken;

	// ======= PC CTRL =======

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
			pc <= 32'h1c00_0000;
		end else if (update_i.flush) begin
			pc <= update_i.br_target;
		end else if (stall_i) begin
			pc <= pc;
		end else begin
			pc <= {npc, 2'b00};
		end
	end

	assign npc = bpu_state == BPU_REFILL || stall_i ? pc[31:2] : ppc;

	// ======= BTB =======
	wire btb_miss;
	wire [$clog2(`_BLOCK_SIZE) - 1:0] btb_choice;
	wire [1:0] btb_br_type;
	wire [31:2] btb_bta;

	btb #(
		.ADDR_WIDTH(`_BTB_ADDR_WIDTH),
		.BLOCK_SIZE(`_BLOCK_SIZE)
	) inst_btb (
		.clk       (clk),
		.rst_n     (rst_n),
		.update_i  (update_i.btb_update),
		.br_type_i (update_i.br_type),
		.rpc_i     (npc),
		.wpc_i     (update_i.pc[31:2]),
		.bta_i     (update_i.br_target[31:2]),
		.miss_o    (btb_miss),
		.choice_o  (btb_choice),
		.br_type_o (btb_br_type),
		.bta_o     (btb_bta)
	);

	// ======= BHT =======


	// TODO


	// ======= LPHT =======
	wire [1:0] lphr;

	pht #(
		.ADDR_WIDTH(`_LPHT_ADDR_WIDTH)
	) inst_lpht (
		.clk      (clk),
		.rst_n    (rst_n),
		.we_i     (update_i.lpht_update),
		.taken_i  (update_i.br_taken),
		.phr_i    (update_i.lphr),
		.rindex_i (npc[`_LPHT_ADDR_WIDTH + 2:3]),
		.windex_i (update_i.pc[`_LPHT_ADDR_WIDTH + 2:3]),
		.phr_o    (lphr)
	);

	// ======= RAS =======

	wire [31:2] ras_target;

	ras #(
		.STACK_DEPTH(`_RAS_STACK_DEPTH)
	) inst_ras (
		.clk      (clk),
		.rst_n    (rst_n),
		.pop_i    (btb_br_type == `_RETURN && ~stall_i),
		.push_i   (btb_br_type == `_CALL && ~stall_i),
		.revoke_i (1'b0), // TODO
		.target_i (npc + 1),
		.ras_top_i    (ras_top_i), // TODO
		.ras_top_ptr_i(ras_top_ptr_i), // TODO
		.target_o 	  (ras_target),
		.ras_top_ptr_o(ras_top_ptr_o)
	);

	// ======= GHR =======

	// reg [`_GHR_DATA_WIDTH - 1:0] ghr;

	// always @(posedge clk ) begin
    //     if (~rst_n) begin
    //         ghr <= 0;
    //     end else if (stall_i) begin
    //         ghr <= ghr;
    //     end else begin
    //         // ghr logic
    //         if (update_i.flush) begin
    //             ghr <= update_i.ghr_checkpoint;
    //         end else begin
    //             ghr <= (ghr << 1) | taken;
    //         end
    //     end
    // end

    // wire [`_GHR_DATA_WIDTH - 1:0] ghr_checkpoint = (ghr << 1) | ~taken;

    // ======= GPHT =======

    // TODO

    // ======= CPHT =======

    // TODO

	// ======= predict logic =======
	// taken = 被预测指令有效 && 预测跳转
	assign taken = (pc[$clog2(`_BLOCK_SIZE) + 1:2] <= btb_choice) && (btb_br_type != `_PC_RELATIVE || lphr[1]);
	assign ppc = btb_br_type == `_RETURN ? ras_target :
				 taken 					 ? btb_bta    : 
				 						   {pc[31:3] + 29'd1, 1'b0};


	// ======= output =======
	assign pc_o = pc;

	assign stall_o = bpu_state == BPU_REFILL;

	generate
		for (genvar i = 0; i < `_BLOCK_SIZE; i++) begin
			assign pc_valid_o[i] = (pc[$clog2(`_BLOCK_SIZE) + 1:2] <= i) && !(taken && btb_choice <= i) && rst_n && !stall_i && !stall_o;
		end
	endgenerate

	assign predict_o.choice = btb_choice;
	assign predict_o.taken = taken;
	assign predict_o.npc = npc;
	assign predict_o.lphr = lphr;
	assign predict_o.lphr_index = pc[`_LPHT_ADDR_WIDTH + 2:3];

endmodule : bpu
