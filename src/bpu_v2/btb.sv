// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : btb.sv
// Create : 2023-01-08 09:57:03
// Revise : 2023-01-10 10:11:39
// Editor : sublime text4, tab size (4)
// -----------------------------------------------------------------------------

`include "include/bpu.svh"

/*                              -btb entry-
    ====================================================================================
    || valid || choice[OFFSET_BLOCK_SIZE - 1:0] || TAG[14:0] || BTA[31：2] || br_type[1:0] ||
    ====================================================================================
*/

module btb #(
    parameter ADDR_WIDTH = 10,
    parameter BLOCK_SIZE = 2
)(
    input clk,    // Clock
    input rst_n,  // Asynchronous reset active low
    input         update_i,
    input  [ 1:0] br_type_i,
    input  [31:2] rpc_i,
    input  [31:2] wpc_i,
    input  [31:2] bta_i,
    output        miss_o,
    output [$clog2(BLOCK_SIZE) - 1:0] choice_o,
    output [ 1:0] br_type_o,
    output [31:2] bta_o
);

    localparam BUFFER_SIZE = 1 << ADDR_WIDTH;
    localparam TAG_WIDTH   = 15;
    localparam ENTRY_WIDTH = 1 + 1 + TAG_WIDTH + 30 + 2;
    localparam OFFSET_BLOCK_SIZE = $clog2(BLOCK_SIZE) + 2;


    function logic[TAG_WIDTH - 1:0] mktag(logic[31:2] pc);
        return pc[31:32 - TAG_WIDTH] ^ pc[TAG_WIDTH + OFFSET_BLOCK_SIZE - 1:OFFSET_BLOCK_SIZE];
    endfunction

    // input
    wire [TAG_WIDTH - 1:0] tag_r = mktag(rpc_i);
    wire [ADDR_WIDTH - 1:0] index_r = rpc_i[ADDR_WIDTH + OFFSET_BLOCK_SIZE - 1:OFFSET_BLOCK_SIZE];
    wire [TAG_WIDTH - 1:0] tag_w = mktag(wpc_i);
    wire [ADDR_WIDTH - 1:0] index_w = wpc_i[ADDR_WIDTH + OFFSET_BLOCK_SIZE - 1:OFFSET_BLOCK_SIZE];

    // ram
    wire en, valid;
    wire [$clog2(BLOCK_SIZE) - 1:0] choice;
    wire [1:0] br_type;
    wire [31:2] bta;
    wire [TAG_WIDTH - 1:0] tag;

    sdpram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (ENTRY_WIDTH)
    ) btb_ram (
        .clk      (clk),
        .rst_n    (rst_n),
        .en_i     (1'b1),
        .we_i     (update_i),
        .raddr_i  (index_r),
        .waddr_i  (index_w),
        .din_i    ({1'b1, wpc_i[$clog2(BLOCK_SIZE) + 1:2], tag_w, bta_i, br_type_i}),
        .dout_o   ({valid, choice, tag, bta, br_type})
    );

    // 1 clk delay for rpc
    reg [31:2] pre_pc;
    wire [TAG_WIDTH - 1:0] pre_tag;
    wire [ADDR_WIDTH - 1:0] pre_index;

    always @(posedge clk ) begin
        if (~rst_n) begin
            pre_pc <= 0;
        end else begin
            pre_pc <= rpc_i;
        end
    end

    assign pre_tag = mktag(pre_pc);
    assign pre_index = pre_pc[ADDR_WIDTH + OFFSET_BLOCK_SIZE - 1:OFFSET_BLOCK_SIZE];

    // output
    wire hit = valid & (tag == pre_tag);
    assign miss_o = ~hit;
    assign choice_o = choice;
    assign bta_o = hit ? bta : {pre_pc[31:3] + 29'd1, 1'b0};
    assign br_type_o = hit ? br_type : `_PC_RELATIVE;

endmodule : btb
