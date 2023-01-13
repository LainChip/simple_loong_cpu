/*
2023-1-13 v1: xrb完成
*/


module boothproduct #(
    parameter int FACIEND_WIDTH = 68 // 被乘数位宽
)(
    input  [2:0] y,
    input  [FACIEND_WIDTH - 1:0] X,
    output [FACIEND_WIDTH - 1:0] P,
    output carry
);

    logic S_negx, S_x, S_neg2x, S_2x;

    /* prepare for select signal */
    assign S_negx = ( y[2] & ~y[1] &  y[0]) | ( y[2] & y[1] & ~y[0]); 
    assign S_x    = (~y[2] & ~y[1] &  y[0]) | (~y[2] & y[1] & ~y[0]); 
    assign S_neg2x= ( y[2] & ~y[1] & ~y[0]); 
    assign S_2x   = (~y[2] &  y[1] &  y[0]); 
    
    /* get P */
    assign P[0] = (S_negx & ~X[0]) | (S_neg2x & ~0) | (S_2x & 0) | (S_x & X[0]); // X[-1] = 0
    generate
        for (genvar i = 1 ; i < FACIEND_WIDTH; i = i + 1) begin
            assign P[i] = (S_negx & ~X[i]) | (S_neg2x & ~X[i-1]) | (S_2x & X[i-1]) | (S_x & X[0]);
        end
    endgenerate 
    /* get carry */
    assign carry = S_negx | S_neg2x;

endmodule
