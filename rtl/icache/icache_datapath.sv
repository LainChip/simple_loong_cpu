`include "common.svh"

// 这个模块生成一路cache的data和tag信息。
// data和tag均使用 single port ram，因此同时只可读 或者只可写
module icache_datapath#(
    parameter int FETCH_SIZE = 2               // 只可选择 1 / 2 / 4
)(
    input clk,
    input rst_n,

    input data_we_i,
    input tag_we_i,
    input [11:2] addr_i,

    output [FETCH_SIZE - 1 : 0][31 : 0] data_o,
    input  [31:0] data_i,

    output [21:0] tag_o,
    input  [21:0] tag_i
);

logic [3:0][31:0] data_raw;
logic [3:2] addr_sel;

always_ff @(posedge clk) begin
    addr_sel <= addr_i[3:2];
end

for(genvar i = 0 ; i < FETCH_SIZE ; i += 1) begin
    if(FETCH_SIZE == 1) begin
        assign data_o = data_raw[addr_sel[3:2]];
    end else if(FETCH_SIZE == 2) begin
        assign data_o[i[0]] = data_raw[{addr_sel[3],i[0]}];
    end else if(FETCH_SIZE == 4) begin // FETCH_SIZE is in {1,2,4}
        assign data_o[i[1:0]] = data_raw[i[1:0]];
    end else begin
        // nothing here
    end
end

// 不需要任何的数据转发，数据raw的处理由额外两个sync状态进行处理。
spram_256x32 sram_block_00(
    .Q(data_raw[2'b00]),   // 输出数据
    .CLK(clk), // 输入时钟
    .CEN(1'b1),
    .A(addr_i[11:4]),   // 输入地址
    .WEN(data_we_i & ~addr_i[3] & ~addr_i[2]), // 输入写使能
    .D(data_i)    // 输入数据
);

spram_256x32 sram_block_01(
    .Q(data_raw[2'b01]),   // 输出数据
    .CLK(clk), // 输入时钟
    .CEN(1'b1),
    .A(addr_i[11:4]),   // 输入地址
    .WEN(data_we_i & ~addr_i[3] & addr_i[2]), // 输入写使能
    .D(data_i)    // 输入数据
);

spram_256x32 sram_block_10(
    .Q(data_raw[2'b10]),   // 输出数据
    .CLK(clk), // 输入时钟
    .CEN(1'b1),
    .A(addr_i[11:4]),   // 输入地址
    .WEN(data_we_i & addr_i[3] & ~addr_i[2]), // 输入写使能
    .D(data_i)    // 输入数据
);

spram_256x32 sram_block_11(
    .Q(data_raw[2'b11]),   // 输出数据
    .CLK(clk), // 输入时钟
    .CEN(1'b1),
    .A(addr_i[11:4]),   // 输入地址
    .WEN(data_we_i & addr_i[3] & addr_i[2]), // 输入写使能
    .D(data_i)    // 输入数据
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

spram_256x22 sram_tag(
    .Q(tag_o),
    .CLK(clk),
    .CEN(1'b1),
    .A(addr_i[11:4] ^ reset_addr_q),
    .WEN(tag_we_i || reset_we_q),
    .D(tag_i)
);

endmodule