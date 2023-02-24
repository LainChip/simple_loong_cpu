// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : ras.sv
// Create : 2023-01-31 20:08:24
// Revise : 2023-02-02 10:32:31
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

module ras  #(
	parameter STACK_DEPTH = 8
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input pop_i,
	input push_i,
    input revoke_i, // TODO, 分支失败时的ras恢复
	input [31:2] target_i,
    input [31:2] ras_top_i,
    input [$clog2(STACK_DEPTH) - 1:0] ras_top_ptr_i,
	output [31:2] target_o,
    output [$clog2(STACK_DEPTH) - 1:0] ras_top_ptr_o
);

	localparam PTR_WIDTH = $clog2(STACK_DEPTH);
    
    reg [31:2] ras [STACK_DEPTH - 1:0];
    reg [PTR_WIDTH - 1:0] ras_ptr;

    wire ras_full;
    wire ras_empty;

    assign ras_full  = (ras_ptr == STACK_DEPTH);
    assign ras_empty = (ras_ptr == 0);

    always @(posedge clk) begin
        if (~rst_n) begin
            ras_ptr <= 0;
        end else if (revoke_i) begin
            ras_ptr <= ras_top_ptr_i;
            ras[ras_top_ptr_i - 1] <= ras_top_i;
        end else begin
            if (push_i && !ras_full) begin
                ras[ras_ptr] <= target_i;
                ras_ptr <= ras_ptr + 1;
            end
            else if (pop_i && !ras_empty) begin
                ras_ptr <= ras_ptr - 1;
            end
        end
    end

    assign target_o = ras[ras_ptr - 1];
    assign ras_top_ptr_o = ras_ptr;

endmodule : ras