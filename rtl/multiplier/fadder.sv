/*
2023-1-13 v1: xrb完成
*/

module fadder (
    input a, b, c,
    output carry, s
);
    // rtl实现
    assign carry = a & b | a & c | b & c;
    assign s = a ^ b ^ c;
    // 不知用原语如何，用与非门还是正常的与/或；不知自定义原语如何

endmodule
