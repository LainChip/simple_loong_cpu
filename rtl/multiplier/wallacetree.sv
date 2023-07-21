/*
2023-1-13 v1: xrb完成
*/

/*--JSON--{"module_name":"deperated","module_ver":"3","module_type":"module"}--JSON--*/
module wallacetree (    /* 17 way wallace tree */
    input  [16:0] in,
    input  [13:0] c_i,
    output [13:0] c_o,
    output c, s
);

    logic [4:0] fir_s;
    /* layer 1 */
    fadder adder1_1(.a(in[16]), .b(in[15]), .c(in[14]), /* --> */ .carry(c_o[4]), .s(fir_s[4]));
    fadder adder1_2(.a(in[13]), .b(in[12]), .c(in[11]), /* --> */ .carry(c_o[3]), .s(fir_s[3]));
    fadder adder1_3(.a(in[10]), .b(in[ 9]), .c(in[ 8]), /* --> */ .carry(c_o[2]), .s(fir_s[2]));
    fadder adder1_4(.a(in[ 7]), .b(in[ 6]), .c(in[ 5]), /* --> */ .carry(c_o[1]), .s(fir_s[1]));
    fadder adder1_5(.a(in[ 4]), .b(in[ 3]), .c(in[ 2]), /* --> */ .carry(c_o[0]), .s(fir_s[0]));


    logic [3:0] sec_s;
    /* layer 2 */
    fadder adder2_1(.a(fir_s[4]), .b(fir_s[3]), .c(fir_s[2]), /* --> */ .carry(c_o[8]), .s(sec_s[3]));
    fadder adder2_2(.a(fir_s[1]), .b(fir_s[0]), .c(   in[1]), /* --> */ .carry(c_o[7]), .s(sec_s[2]));
    fadder adder2_3(.a(   in[0]), .b(  c_i[4]), .c(  c_i[3]), /* --> */ .carry(c_o[6]), .s(sec_s[1]));
    fadder adder2_4(.a(  c_i[2]), .b(  c_i[1]), .c(  c_i[0]), /* --> */ .carry(c_o[5]), .s(sec_s[0]));


    logic [1:0] thi_s;
    /* layer 3 */
    fadder adder3_1(.a(sec_s[3]), .b(sec_s[2]), .c(sec_s[1]), /* --> */ .carry(c_o[10]), .s(thi_s[1]));
    fadder adder3_2(.a(sec_s[0]), .b(  c_i[6]), .c(  c_i[5]), /* --> */ .carry(c_o[ 9]), .s(thi_s[0]));

    
    logic [1:0] fou_s;
    /* layer 4 */
    fadder adder4_1(.a(thi_s[1]), .b(thi_s[0]), .c( c_i[10]), /* --> */ .carry(c_o[12]), .s(fou_s[1]));
    fadder adder4_2(.a(  c_i[9]), .b(  c_i[8]), .c( c_i[ 7]), /* --> */ .carry(c_o[11]), .s(fou_s[0]));


    logic fif_s;
    /* layer 5 */
    fadder adder5_1(.a(fou_s[1]), .b(fou_s[0]), .c(c_i[11]), /* --> */ .carry(c_o[13]), .s(fif_s));


    /* layer 6 */
    fadder adder6_1(.a(fif_s), .b(c_i[13]), .c(c_i[12]), /* --> */ .carry(c), .s(s));

endmodule
