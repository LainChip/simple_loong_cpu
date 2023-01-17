/*
2023-1-13 v1: xrb完成
*/

module multiplier (
    input clk,
    input rst_n,

    input mul_signed_i,
    input  [31:0] X_i,
    input  [31:0] Y_i,
    output [63:0] res_o
);
    // for gtkwave
    // initial begin
    // 	$dumpfile("logs/vlt_dump.vcd");
    // 	$dumpvars();
    // end

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
    always_comb begin
        for (int i = 0; i < 68; i = i + 1) begin
            for (int j = 0; j < 17; j = j + 1) begin
                wallace_datain[i][j] = booth_product[j][i];
            end
        end
    end


    /*======= through wallace tree =======*/
    logic [67:0][13:0] wallace_carrypath; // ...[67] is useless 
    logic [67:0] wallace_c, wallace_s;
    wallacetree wallace_bit_0(
        .in(wallace_datain[0]),
        .c_i(booth_carry[13:0]),
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


    /*======= final 68bit add, and select [63:0] part =======*/
    assign res_o = {wallace_c[62:0], booth_carry[14]} + wallace_s[63:0] + {62'b0, booth_carry[15]};


endmodule
