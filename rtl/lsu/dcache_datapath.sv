`include "common.svh"

// 这个模块生成一路cache的data和tag信息。
// data和tag均使用 dual port ram
module dcache_datapath(
    input clk,
    input rst_n,

    input [3:0]data_we_i,
    input tag_we_i,
    input [11:2] r_addr_i,
    input [11:2] w_addr_i,

    output [31 : 0] data_o,
    input  [31 : 0] data_i,

    output [21:0] tag_o,
    input  [21:0] tag_i
);

    simpleDualPortRamByteen #(
        .dataWidth(32),
        .ramSize(1024),
        .readMuler(1),
        .latency(1)
    ) data_ram (
        .clk,      // Clock
	    .rst_n,    // Asynchronous reset active low
	    .addressA(w_addr_i), // 写地址
	    .we(data_we_i),
	    .addressB(r_addr_i), // 读地址
	    .inData(data_i),
	    .outData(data_o)
    );

logic[7:0] reset_addr_q;
logic reset_we_q;
// if(need_reset) begin
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            reset_addr_q <= reset_addr_q + 1;
            reset_we_q <= '1;
        end else begin
            reset_addr_q <= '0;
            reset_we_q <= '0;
        end
    end
// else begin

// end
    simpleDualPortRam #(
        .dataWidth(22),
        .ramSize(256),
        .readMuler(1),
        .latency(1)
    ) tag_ram (
        .clk,
        .rst_n,
        .addressA(w_addr_i[11:4] ^ reset_addr_q),
        .we(tag_we_i || reset_we_q),
        .addressB(r_addr_i[11:4]),
        .inData(tag_i),
        .outData(tag_o)
    );


endmodule