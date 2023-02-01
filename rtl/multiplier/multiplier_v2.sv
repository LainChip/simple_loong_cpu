/*
2023-1-22 v2: 划分了3级流水（booth部分积 | wallace树 | 68位加法器）
*/

`include "common.svh"

`ifdef __MULTIPLIER_VER_2

module multiplier_v2 (
    input clk,
    input rst_n,

    input [1:0] stall_i,    // stall_i : [0] for m1, [1] for m2

    input mul_signed_i,
    input  [31:0] X_i,
    input  [31:0] Y_i,
    output [63:0] res_o
);
    // for unit test: dump waves for gtkwave
    // `ifndef _DIFFTEST_ENABLE
    //     initial begin
    //     	$dumpfile("logs/vlt_dump.vcd");
    //     	$dumpvars();
    //     end
    // `endif

    typedef struct packed {
        logic [16:0] booth_carry;
        logic [63:0] wallace_c, wallace_s;
    } mul_flow_t;

    mul_flow_t mul_stage_2, mul_stage_3;

    ////////////////// Stage 1 //////////////////

    /*======= deal with sign =======*/
    logic [67:0] faciend_X;
    logic [33:0] factor_Y;
    assign faciend_X = mul_signed_i ? {{36{X_i[31]}}, X_i} : {36'b0, X_i};
    assign factor_Y  = mul_signed_i ? {{ 2{Y_i[31]}}, Y_i} : { 2'b0, Y_i};


    /*======= generate booth part products =======*/
    logic [16:0][67:0] booth_product;   // has 17 part products
    logic [16:0] booth_carry;
    boothproduct #(
        .FACIEND_WIDTH(68)
    ) part_product_0 (
        .y({factor_Y[1:0], 1'b0}), 
        .X(faciend_X),
        // output
        .P(booth_product[0]), 
        .carry(booth_carry[0])
    );

    generate
        for (genvar i = 2; i < 34; i = i + 2) begin
            /* other 16 boothproduct */
            boothproduct #(
                .FACIEND_WIDTH(68)
            ) part_product_i (
                .y(factor_Y[i+1 : i-1]), 
                .X(faciend_X << i),
                // output
                .P(booth_product[i >> 1]), 
                .carry(booth_carry[i >> 1])
            );     
        end
    endgenerate


    /*======= switch signal, prepared to enter wallace tree =======*/
    logic [67:0][16:0] wallace_datain; // 17 numbers add together, each has 68 bits 
    // also, enter stage 2
    always_ff @(posedge clk) begin
        if (~rst_n) begin
            wallace_datain <= 0;
            mul_stage_2 <= 0;
        end else if (~stall_i[0]) begin
            for (int i = 0; i < 68; i = i + 1) begin
                for (int j = 0; j < 17; j = j + 1) begin
                    wallace_datain[i][j] <= booth_product[j][i];
                end
            end
            mul_stage_2.booth_carry <= booth_carry;
        end
    end

    ////////////////// Stage 2 //////////////////

    /*======= through wallace tree =======*/
    logic [67:0][13:0] wallace_carrypath; // ...[67] is useless 
    logic [67:0] wallace_c, wallace_s;
    wallacetree wallace_bit_0(
        .in(wallace_datain[0]),
        .c_i(mul_stage_2.booth_carry[13:0]),
        // output
        .c_o(wallace_carrypath[0]),
        .c(wallace_c[0]),
        .s(wallace_s[0])
    );

    generate
        for (genvar i = 1; i < 68; i = i + 1) begin
            wallacetree wallace_bit_i(
                .in(wallace_datain[i]),
                .c_i(wallace_carrypath[i-1]),
                // output
                .c_o(wallace_carrypath[i]),
                .c(wallace_c[i]),
                .s(wallace_s[i])
            );
        end
    endgenerate


    always_ff @(posedge clk) begin
        if (~rst_n) begin
            mul_stage_3 <= 0;
        end else if (~stall_i[1]) begin
            mul_stage_3.booth_carry <= mul_stage_2.booth_carry;
            mul_stage_3.wallace_c <= wallace_c[63:0];
            mul_stage_3.wallace_s <= wallace_s[63:0];
        end
    end

    ////////////////// Stage 3 //////////////////

    /*======= final 68bit add, and select [63:0] part =======*/
    assign res_o = {mul_stage_3.wallace_c[62:0], mul_stage_3.booth_carry[14]} + 
                    mul_stage_3.wallace_s + 
                    {62'b0, mul_stage_3.booth_carry[15]};


endmodule

`endif
