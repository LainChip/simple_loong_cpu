module spram_256x32(
    output wire [31:0] Q,
    input  wire        CLK,
    input  wire        CEN, 
    input  wire [ 7:0] A,
    input  wire        WEN, 
    input  wire [31:0] D
);

// S018RF1P_X128Y2D32_PM ram(
//        .Q     (Q),
//        .CLK   (CLK),
//        .CEN   (CEN),
//        .WEN   (WEN),
//        .A     (A),
//        .D     (D)
// );
// sim_sram #(
//     .WIDTH(32),
//     .DEPTH(256)
// ) ram(
//     .addra(A),
//     .clka(CLK),
//     .dina(D),
//     .douta(Q),
//     .ena(CEN),
//     .wea(WEN)
// );

    simpleDualPortRam #(
        .dataWidth(32),
        .ramSize(256),
        .readMuler(1),
        .latency(1)
    ) tag_ram (
        .clk(CLK),
        .rst_n(1'd1),
        .addressA(A),
        .we(WEN & CEN),
        .addressB(A),
        .inData(D),
        .outData(Q)
    );

endmodule