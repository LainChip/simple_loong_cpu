`include "common.svh"

//  使用round robin算法，在多个请求之间进行公平调度。
module arbiter_round_robin #(
	parameter int REQ_NUM = 4
	)(
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input take_sel_i,
	input  logic[REQ_NUM - 1 : 0] req_i,
	output logic[REQ_NUM - 1 : 0] sel_o
);
// Print some stuff as an example
//    initial begin
//     	$dumpfile("logs/vlt_dump.vcd");
//     	$dumpvars();
//    end

	logic[2 * REQ_NUM - 1 : 0] round_robin_mask,round_robin_mask_next,masked_req;
	logic[REQ_NUM - 1 : 0] round_robin_sel_onehot;
	logic valid_sel;

	assign valid_sel = |req_i;
	assign masked_req = round_robin_mask & {req_i,req_i};
	assign round_robin_mask_next = {(round_robin_sel_onehot - {REQ_NUM{1'd1}}),(~(round_robin_sel_onehot - {REQ_NUM{1'd1}}))};
	assign sel_o = round_robin_sel_onehot;
	// assign sel_o = '0;

	always_comb begin : round_robin_sel_onehot_gen
		round_robin_sel_onehot = '0;
		for(integer i = 0 ; i < (2 * REQ_NUM) ; i += 1) begin : round_robin_sel_onehot_loop
			if(masked_req[i]) begin
				round_robin_sel_onehot = '0;
				round_robin_sel_onehot[i[$clog2(REQ_NUM) - 1 : 0]] = 1'b1;
			end
		end
	end

	always_ff @(posedge clk) begin : proc_round_robin_mask
		if(~rst_n) begin
			round_robin_mask <= '0;
		end else if(valid_sel & take_sel_i) begin
			round_robin_mask <= round_robin_mask_next;
		end
	end

endmodule
