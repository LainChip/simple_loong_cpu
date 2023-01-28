`include "common.svh"
module spram_256x22(
    output wire [21:0] Q,
    input  wire        CLK,
    input  wire        CEN, 
    input  wire [ 7:0] A,
    input  wire        WEN, 
    input  wire [21:0] D
);

// S018RF1P_X128Y2D22_PM ram(
//        .Q     (Q),
//        .CLK   (CLK),
//        .CEN   (CEN),
//        .WEN   (WEN),
//        .A     (A),
//        .D     (D)
// );
sim_sram #(
    .WIDTH(22),
    .DEPTH(256)
) ram(
    .addra(A),
    .clka(CLK),
    .dina(D),
    .douta(Q),
    .ena(CEN),
    .wea(WEN)
);

endmodule