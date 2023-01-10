// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : btb_2way.sv
// Create : 2023-01-08 08:48:44
// Revise : 2023-01-08 18:51:59
// Editor : sublime text4, tab size (4)
// -----------------------------------------------------------------------------

`include "bpu.svh"

module btb #(
    parameter ADDR_WIDTH = `_BTB_ADDR_WIDTH,
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

    logic en0, en1, we0, we1, valid0, valid1;
    logic [ 1: 0] Br_type0, Br_type1;
    logic [31: 2] bta0, bta1;
    logic [TAG_WIDTH - 1: 0] tag0, tag1;

    // reg
    logic lru_reg [ 0: 1 << ADDR_WIDTH];
    logic [31: 2] pre_pc; // store pre pc to renew lru
    logic [TAG_WIDTH - 1:0] pre_tag;
    logic [ADDR_WIDTH - 1:0] pre_index;

    
    wire new_lru = reset ? 1'b0 : 
                   tag0 == pre_tag & valid0 ? 1'b0 : 
                   tag1 == pre_tag & valid1 ? 1'b1 :
                   1'b0;

    always_ff @(posedge clk) begin
        if (reset) begin
            for (integer i = 0; i < 1 << ADDR_WIDTH; i = i + 1) begin
                lru_reg[i] <= 1'b0; 
            end
        end else begin
            lru_reg[pre_index] <= new_lru;
        end
    end

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

    wire hit = (valid0 & tag0 == pre_tag) | (valid1 & tag1 == pre_tag);
    assign we0 = index_w == pre_index ? we &  new_lru : we &  lru_reg[index_w];
    assign we1 = index_w == pre_index ? we & ~new_lru : we & ~lru_reg[index_w];
    assign bta_o = valid0 & tag0 == pre_tag ? bta0 : 
                   valid1 & tag1 == pre_tag ? bta1 :
                   pre_pc + 2'b10;
    assign Br_type_o = valid0 & tag0 == pre_tag ? Br_type0 : 
                       valid1 & tag1 == pre_tag ? Br_type1 :
                       `_PC_RELATIVE;
    assign miss = ~hit;

    // ram
    sdpram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (ENTRY_WIDTH)
    ) way0 (
        .clk    (clk),
        .reset  (reset),
        .en     (1'b1),
        .we     (we0),
        .raddr  (index_r),
        .waddr  (index_w),
        .wdata  ({1'b1, tag_w, bta_i, Br_type_i}),
        .rdata  ({valid0, tag0, bta0, Br_type0})
    );

    sdpram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (ENTRY_WIDTH)
    ) way1 (
        .clk    (clk),
        .reset  (reset),
        .en     (1'b1),
        .we     (we1),
        .raddr  (index_r),
        .waddr  (index_w),
        .wdata  ({1'b1, tag_w, bta_i, Br_type_i}),
        .rdata  ({valid1, tag1, bta1, Br_type1})
    );

endmodule
