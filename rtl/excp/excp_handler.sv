`include "common.svh"
`include "decoder.svh"
`include "csr.svh"

module excp_handler(
    input decode_info_t decode_info_i,
    input logic [31:0] vpc_i,

    output logic [5:0]  ecode_o,            //输出：两条流水线的例外一级码
    output logic [8:0]  esubcode_o,         //输出：两条流水线的例外二级码
    output logic        excp_trigger_o,     //输出：是否发生异常
    output logic [31:0] bad_va_o            //输出：地址相关例外出错的虚地址
);

    always_comb begin
        ecode_o = '0;
        esubcode_o = '0;
        excp_trigger_o = '0;
        bad_va_o = vpc_i;
        // 目前仅仅处理syscall 和 break 和 INE三个异常
        if(decode_info_i.m2.exception_hint == `_EXCEPTION_HINT_SYSCALL) begin
            ecode_o = (decode_info_i.general.inst25_0[16]) ? 6'b001011 : 6'b001100;
            excp_trigger_o = '1;
        end else if(decode_info_i.m2.exception_hint == `_EXCEPTION_HINT_INVALID) begin
            ecode_o = 6'hd; // INE
            excp_trigger_o = '1;
        end
    end

endmodule