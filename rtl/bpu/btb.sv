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
    output [31:2] bta_o [1:0],
    output [ 1:0] Br_type_o [1:0]
);

/*                              -btb entry-
    =======================================================
    || valid || TAG[14:0] || BTA[31：2] || Br_type[1 :0] ||
    =======================================================
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
    logic valid [1:0];
    logic [ 1: 0] Br_type [1:0];
    logic [31: 2] bta [1:0];
    logic [TAG_WIDTH - 1: 0] tag [1:0];

    logic rst_q;
    logic [ADDR_WIDTH - 1 : 0] rst_addr_q;
    always_ff @(posedge clk) begin
        rst_q <= !rst_n;
        if(rst_n) begin
            rst_addr_q <= '0;
        end else begin
            rst_addr_q <= rst_addr_q + 1;
        end
    end
    simpleDualPortRam #(
        .dataWidth(ENTRY_WIDTH),
        .ramSize(1 << (ADDR_WIDTH - 1)),
        .readMuler(1)
    ) inst_bank0 (
        .clk      (clk),
        .rst_n    (rst_n),
        .addressA (index_w ^ rst_addr_q),
        .we       ((update_i && !wpc_i[2]) || rst_q),
        .addressB (index_r),
        .inData   ({!rst_q, tag_w, bta_i, Br_type_i}),
        .outData  ({valid[0], tag[0], bta[0], Br_type[0]})
    );

    simpleDualPortRam #(
        .dataWidth(ENTRY_WIDTH),
        .ramSize(1 << (ADDR_WIDTH - 1)),
        .readMuler(1)
    ) inst_bank1 (
        .clk      (clk),
        .rst_n    (rst_n),
        .addressA (index_w ^ rst_addr_q),
        .we       ((update_i && wpc_i[2]) || rst_q),
        .addressB (index_r),
        .inData   ({!rst_q, tag_w, bta_i, Br_type_i}),
        .outData  ({valid[1], tag[1], bta[1], Br_type[1]})
    );


    // 1 clk delay for rpc
    logic [31: 2] pre_pc;
    logic [TAG_WIDTH - 1:0] pre_tag;

    always @(posedge clk ) begin
        if (~rst_n) begin
            pre_pc <= 0;
        end else begin
            pre_pc <= rpc_i;
        end
    end

    assign pre_tag = mktag(pre_pc);

    // output
    logic hit [1:0];
    assign hit[0] = valid[0] & tag[0] == pre_tag;
    assign hit[1] = valid[1] & tag[1] == pre_tag;
    assign bta_o[0] = hit[0] ? bta[0] : {pre_pc[31:3] + 29'd1, 1'b0};
    assign Br_type_o[0] = hit[0] ? Br_type[0] : `_PC_RELATIVE;
    
    assign bta_o[1] = hit[1] ? bta[1] : {pre_pc[31:3] + 29'd1, 1'b0};
    assign Br_type_o[1] = hit[1] ? Br_type[1] : `_PC_RELATIVE;

endmodule : btb
