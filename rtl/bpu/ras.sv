// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : ras.sv
// Create : 2023-01-08 19:14:41
// Revise : 2023-01-10 09:59:50
// Editor : sublime text4, tab size (4)
// -----------------------------------------------------------------------------

`include "bpu.svh"

module ras #(
	parameter STACK_DEPTH = `_RAS_STACK_DEPTH
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous rst_n active low
	input pop_i,
    input push_i,
    input  [31:2] target_i,
    output [31:2] target_o
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
        end
        else begin
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

endmodule : ras
