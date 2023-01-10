// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : ras.sv
// Create : 2023-01-08 19:14:41
// Revise : 2023-01-08 19:26:17
// Editor : sublime text4, tab size (4)
// -----------------------------------------------------------------------------

`include "bpu.svh"

module ras #(
	parameter WRITE_GUARD = `_RAS_WRITE_GUARD,
	parameter STACK_WIDTH = `_RAS_STACK_WIDTH
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous rst_n active low
	input pop_i,
    input push_i,
    input  [31:2] din,
    output full,
    output empty,
    output [31:2] dout
);

	localparam STACK_DEPTH = 1 << STACK_WIDTH;
    
    reg [31:0] ras [STACK_DEPTH - 1:0];

    reg		[STACK_WIDTH - 1:0]	sp;	// Stack Point
    wire    we;
    wire    [31:0] rdata; // ram read data
    reg     [31:0] din_buffer;
    reg     push_i_buffer;
    reg     pop_i_buffer;
    reg     empty_buffer;
    generate
        if (WRITE_GUARD == "NO") begin
            assign we = push_i & ~pop_i & ~full;
        end else begin
            assign we = push_i & ~pop_i;
        end
    endgenerate
    assign dout =   (push_i_buffer & pop_i_buffer)  ? din_buffer : 
                    (pop_i_buffer & ~empty_buffer) ? rdata : 32'b0;
    wire [STACK_WIDTH - 1:0] addr = we ? sp : sp - 1;
    // RAM control

    always @(posedge clk ) begin
        if (~rst_n) begin
            din_buffer <= 32'b0;
            push_i_buffer <= 1'b0;
            pop_i_buffer <= 1'b0;
            empty_buffer <= 1'b0;
        end else begin
            din_buffer <= din;
            push_i_buffer <= push_i;
            pop_i_buffer <= pop_i;
            empty_buffer <= empty;
        end
    end

    generate
        if( WRITE_GUARD == "ON" ) begin
            always @(posedge clk ) begin
                if (~rst_n) begin
                    sp <= 0;
                end else if (push_i && pop_i) begin
                    sp <= sp;
                end else if (push_i && ~full) begin
                    sp <= sp + 1;
                end else if (pop_i && ~empty) begin
                    sp <= sp - 1;
                end else begin
                    sp <= sp;
                end
            end
        end else begin
            always @(posedge clk ) begin
                if (~rst_n) begin
                    sp <= 0;
                end else if (push_i && pop_i) begin
                    sp <= sp;
                end else if (push_i) begin
                    sp <= sp + 1;
                end else if (pop_i && ~empty) begin
                    sp <= sp - 1;
                end else begin
                    sp <= sp;
                end
            end
        end
    endgenerate

    // spram #(
    //     .ADDR_WIDTH ( STACK_WIDTH   ),
    //     .DATA_WIDTH ( 32            ),
    //     .WRITE_MODE ( "read_first"  )
    // ) u_spram (
    //     .clk                     ( clk     ),
    //     .~rst_n                   ( ~rst_n   ),
    //     .en                      ( 1'b1    ),
    //     .we                      ( we      ),
    //     .addr                    ( addr    ),
    //     .wdata                   ( din     ),

    //     .rdata                   ( rdata   )
    // );

    assign rdata = ras[addr];
    always @(posedge clk ) begin
        if (~rst_n) begin
            integer i;
            for (i = 0; i < STACK_DEPTH ; i = i + 1) begin
                ras[i] <= 32'h0000_0000;
            end
        end else if (we) begin
            ras[addr] <= din;
        end else begin
            ras[addr] <= ras[addr];
        end
    end
    
    // full and empty
    reg [STACK_WIDTH:0] count;

    always @(posedge clk ) begin
        if (~rst_n) begin
            count <= 0;
        end else begin
            if (push_i && pop_i) begin
                count <= count;
            end else if (push_i && ~full) begin
                count <= count + 1;
            end else if (pop_i && ~empty) begin
                count <= count - 1;
            end else begin
                count <= count;
            end
        end
    end

    assign full = count == STACK_DEPTH;
    assign empty = count == 0;

endmodule : ras