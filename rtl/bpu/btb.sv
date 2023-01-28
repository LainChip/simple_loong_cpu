// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : btb.sv
// Create : 2023-01-08 09:57:03
// Revise : 2023-01-10 10:11:39
// Editor : sublime text4, tab size (4)
// -----------------------------------------------------------------------------

`include "bpu.svh"

module btb #(
    parameter ADDR_WIDTH = 10
)(
    input clk,    // Clock
    input rst_n,  // Asynchronous reset active low
    input  [31:2] rpc_i,
    input         update_i,
    input  [31:2] wpc_i,
    input  [31:2] bta_i,
    input  [ 1:0] Br_type_i,
    output        miss_o,
    output        fsc_o,
    output [31:2] bta_o,
    output [ 1:0] Br_type_o
);

/*                              -btb entry-
    ==============================================================
    || valid || fsc || TAG[14:0] || BTA[31：2] || Br_type[1 :0] ||
    ==============================================================
*/
    function logic[14:0] mktag(logic[31:2] pc);
        return pc[31:17] ^ pc[17:3];
    endfunction

    localparam BUFFER_SIZE = 1 << ADDR_WIDTH;
    localparam TAG_WIDTH   = 15;
    localparam ENTRY_WIDTH = 1 + 1 + TAG_WIDTH + 30 + 2;

    // input
    logic [TAG_WIDTH - 1:0] tag_r;
    logic [ADDR_WIDTH - 1:0] index_r;
    logic [TAG_WIDTH - 1:0] tag_w;
    logic [ADDR_WIDTH - 1:0] index_w;
    assign tag_r = mktag(rpc_i);
    assign index_r = rpc_i[ADDR_WIDTH + 2:3];
    assign tag_w = mktag(wpc_i);
    assign index_w = wpc_i[ADDR_WIDTH + 2:3];


    // ram
    logic en, valid, fsc;
    logic [ 1: 0] Br_type;
    logic [31: 2] bta;
    logic [TAG_WIDTH - 1: 0] tag;

    sdpram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (ENTRY_WIDTH)
    ) way0 (
        .clk    (clk),
        .rst_n  (rst_n),
        .en     (1'b1),
        .we     (update_i),
        .raddr  (index_r),
        .waddr  (index_w),
        .wdata  ({1'b1, wpc_i[2], tag_w, bta_i, Br_type_i}),
        .rdata  ({valid, fsc, tag, bta, Br_type})
    );

    // 1 clk delay for rpc
    logic [31: 2] pre_pc;
    logic [TAG_WIDTH - 1:0] pre_tag;
    logic [ADDR_WIDTH - 1:0] pre_index;

    always @(posedge clk ) begin
        if (~rst_n) begin
            pre_pc <= 0;
        end else begin
            pre_pc <= rpc_i;
        end
    end

    assign pre_tag = mktag(pre_pc);
    assign pre_index = pre_pc[ADDR_WIDTH + 2:3];

    // output
    wire hit = valid & tag == pre_tag;
    assign miss_o = ~hit;
    assign fsc_o = fsc;
    assign bta_o = valid & tag == pre_tag ? bta : {pre_pc[31:3] + 29'd1, 1'b0};
    assign Br_type_o = valid & tag == pre_tag ? Br_type : `_PC_RELATIVE;

endmodule : btb
