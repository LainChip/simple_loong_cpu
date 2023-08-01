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
    input [1:0] redirect_i, // 分支预测器重定向
    input [$clog2(STACK_DEPTH) - 1:0] stack_ptr_i,
    input [31:2] redirect_target_i,
    input  [31:2] target_i,
    output [31:2] target_o,
    output [$clog2(STACK_DEPTH) - 1:0] stack_ptr_o
);

	localparam PTR_WIDTH = $clog2(STACK_DEPTH);
    
    reg [31:2] ras [STACK_DEPTH - 1:0];
    reg [PTR_WIDTH - 1:0] ras_ptr;

    always @(posedge clk) begin
        if (~rst_n) begin
            ras_ptr <= 0;
        end else if (redirect_i == 'd1) begin
            ras_ptr <= stack_ptr_i;
        end else if (redirect_i == 'd2) begin
            ras_ptr <= stack_ptr_i;
            ras[stack_ptr_i - 'd1] <= redirect_target_i;
        end else begin
            if (push_i) begin
                ras[ras_ptr] <= target_i;
                ras_ptr <= ras_ptr + 1;
            end
            else if (pop_i) begin
                ras_ptr <= ras_ptr - 1;
            end
        end
    end

    assign target_o = ras[ras_ptr - 1];
    assign stack_ptr_o = ras_ptr;

    // for debug
    // generate
    //     wire [31:0] ras_32 [STACK_DEPTH - 1:0];
    //     genvar i;
    //     for (i = 0; i < 8; i++) begin
    //         assign ras_32[i] = {ras[i], 2'b00}; 
    //     end
    // endgenerate

endmodule : ras
