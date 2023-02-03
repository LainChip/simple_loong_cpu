`include "common.svh"
`include "decoder.svh"
`include "csr.svh"

module excp_handler(
    input decode_info_t decode_info_i,
    input logic [31:0] vpc_i,
    input logic [31:0] vlsu_i,
    input excp_flow_t excp_i,
    input logic trans_en_i,
    input mmu_resp_t mmu_resp_i,
    input logic[1:0] plv_i,

    output logic [5:0]  ecode_o,            //输出：两条流水线的例外一级码
    output logic [8:0]  esubcode_o,         //输出：两条流水线的例外二级码
    output logic        excp_trigger_o,     //输出：是否发生异常
    output logic [31:0] bad_va_o,           //输出：地址相关例外出错的虚地址
    output logic        va_error_o,
    output logic        tlbrefill_o
);

    always_comb begin
        va_error_o = '0;
        tlbrefill_o = '0;
        ecode_o = '0;
        esubcode_o = '0;
        excp_trigger_o = '0;
        bad_va_o = vpc_i;
        if(excp_i.adef) begin // ADEF
            ecode_o = `_ECODE_ADEF;
            excp_trigger_o = '1;
            va_error_o = '1;
        end else 
        if(excp_i.itlbr) begin // ITLBR
            ecode_o = `_ECODE_TLBR;
            excp_trigger_o = '1;
            va_error_o = '1;
            tlbrefill_o = '1;
        end else 
        if(excp_i.pif) begin // PIF
            ecode_o = `_ECODE_PIF;
            excp_trigger_o = '1;
            va_error_o = '1;
        end else 
        if(excp_i.ippi) begin // IPPI
            ecode_o = `_ECODE_PPI;
            excp_trigger_o = '1;
            va_error_o = '1;
        end else 
        if(decode_info_i.m2.exception_hint == `_EXCEPTION_HINT_SYSCALL) begin // SYS / BRK
            ecode_o = (decode_info_i.general.inst25_0[16]) ? `_ECODE_SYS : `_ECODE_BRK;
            excp_trigger_o = '1;
        end else 
        if((decode_info_i.m2.exception_hint == `_EXCEPTION_HINT_INVALID) || (decode_info_i.m2.invtlb_en && decode_info_i.general.inst25_0[4:0] > 5'd6)) begin // INE
            ecode_o = `_ECODE_INE;
            excp_trigger_o = '1;
        end else
        if(excp_i.ipe) begin // IPE
            ecode_o = 6'h8;
            excp_trigger_o = '1;
        end else 
        if(excp_i.ale) begin  // ALE
            ecode_o = `_ECODE_ALE;
            excp_trigger_o = '1;
            bad_va_o = vlsu_i;
            va_error_o = '1;
        end else 
        if(excp_i.adem) begin  // ADEM
            ecode_o = `_ECODE_ADEM;
            excp_trigger_o = '1;
            bad_va_o = vlsu_i;
            va_error_o = '1;
        end else 
        if(excp_i.adef) begin // DTLBR
            ecode_o = `_ECODE_TLBR;
            excp_trigger_o = '1;
            bad_va_o = vlsu_i;
            va_error_o = '1;
        end else 
        if(trans_en_i && mmu_resp_i.v && mmu_resp_i.d && decode_info_i.m1.mem_write) begin // PME
            ecode_o = `_ECODE_PME;
            excp_trigger_o = '1;
            bad_va_o = vlsu_i;
            va_error_o = '1;
        end else 
        if(trans_en_i && mmu_resp_i.v && (plv_i > mmu_resp_i.plv) && decode_info_i.m1.mem_valid) begin // DPPI
            ecode_o = `_ECODE_PPI;
            excp_trigger_o = '1;
            bad_va_o = vlsu_i;  
            va_error_o = '1;
        end else 
        if(trans_en_i && !mmu_resp_i.v) begin // PIS / PIL
            ecode_o = decode_info_i.m1.mem_write ? `_ECODE_PIS : `_ECODE_PIL;
            excp_trigger_o = '1;
            va_error_o = '1;
        end
    end
endmodule
