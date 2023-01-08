// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : btb.sv
// Create : 2023-01-08 09:57:03
// Revise : 2023-01-08 10:06:46
// Editor : sublime text4, tab size (4)
// -----------------------------------------------------------------------------

`include "bpu.svh"

module btb #(
    parameter ADDR_WIDTH = `BTB_ADDR_WIDTH,
    parameter BANK = 1
)(
    input         clk,
    input         reset,
    input  [31:2] rpc,
    input         we,
    input  [31:2] wpc,
    input  [31:2] bta_i,
    input  [ 1:0] Br_type_i,
    output        miss,
    output [31:2] bta_o,
    output [ 1:0] Br_type_o
    );

/*                      -btb entry-
    =======================================================
    || valid || BIA[14:0] || BTA[31：2] || Br_type[1 :0] ||
    =======================================================
*/
    function logic[14:0] mktag(logic[31:2] pc);
        return {pc[31:17] ^ pc[16:2]};
    endfunction

    localparam BUFFER_SIZE = 1 << ADDR_WIDTH;
    localparam TAG_WIDTH   = 15;
    localparam ENTRY_WIDTH = 1 + TAG_WIDTH + 30 + 2;

    // wire
    logic [TAG_WIDTH - 1:0] tag_r;
    logic [ADDR_WIDTH - 1:0] index_r;
    logic [TAG_WIDTH - 1:0] tag_w;
    logic [ADDR_WIDTH - 1:0] index_w;
    assign tag_r = mktag(rpc);
    assign index_r = rpc[ADDR_WIDTH + 1 + BANK:2 + BANK];
    assign tag_w = mktag(wpc);
    assign index_w = wpc[ADDR_WIDTH + 1 + BANK:2 + BANK];

    logic en, valid;
    logic [ 1: 0] Br_type;
    logic [31: 2] bta;
    logic [TAG_WIDTH - 1: 0] tag;

    // reg
    logic [31: 2] pre_pc; // store pre pc to renew lru
    logic [TAG_WIDTH - 1:0] pre_tag;
    logic [ADDR_WIDTH - 1:0] pre_index;

    wire hit = valid & tag == pre_tag;

    always @(posedge clk ) begin
        if (reset) begin
            pre_pc <= 0;
            pre_index <= 0;
            pre_tag <= 0;
        end else begin
            pre_pc    <= rpc;
            pre_index <= index_r;
            pre_tag   <= tag_r;
        end
    end

    assign bta_o = valid & tag == pre_tag ? bta : pre_pc + 8;
    assign Br_type_o = valid & tag == pre_tag ? Br_type : `PC_RELATIVE;
    assign miss = ~hit;

    // ram
    sdpram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (ENTRY_WIDTH)
    ) way0 (
        .clk    (clk),
        .reset  (reset),
        .en     (1'b1),
        .we     (we),
        .raddr  (index_r),
        .waddr  (index_w),
        .wdata  ({1'b1, tag_w, bta_i, Br_type_i}),
        .rdata  ({valid, tag, bta, Br_type})
    );

endmodule