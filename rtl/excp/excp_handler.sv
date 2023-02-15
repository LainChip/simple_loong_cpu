`include "common.svh"
`include "decoder.svh"
`include "csr.svh"
`include "tlb.svh"

module excp_handler(
    input decode_info_t decode_info_i,
    input logic [31:0] vpc_i,
    input logic [31:0] vlsu_i,
    input excp_flow_t excp_i,
    input logic trans_en_i,
    input mmu_s_resp_t mmu_resp_i,
    input logic[1:0] plv_i,
    input logic llbit_i,

    (* mark_debug="true" *) output logic [5:0]  ecode_o,            //输出：两条流水线的例外一级码
    output logic [8:0]  esubcode_o,         //输出：两条流水线的例外二级码
    (* mark_debug="true" *) output logic        excp_trigger_o,     //输出：是否发生异常
    output logic [31:0] bad_va_o,           //输出：地址相关例外出错的虚地址
    (* mark_debug="true" *) output logic        va_error_o,
    (* mark_debug="true" *) output logic        tlbrefill_o,
    (* mark_debug="true" *) output logic        tlbehi_update_o,
    (* mark_debug="true" *) output logic        ipe_o
);

    logic read_inst;
    logic write_inst;
    logic mem_inst;
    assign read_inst = decode_info_i.m1.mem_valid && ~decode_info_i.m1.mem_write;
    
    // 对于sc指令，当llbit无效时候不产生异常
    assign write_inst = decode_info_i.m1.mem_write && (!decode_info_i.m2.llsc || llbit_i);
    assign mem_inst = write_inst || read_inst;

    always_comb begin
        va_error_o = '0;
        tlbrefill_o = '0;
        ipe_o = '0;
        ecode_o = '0;
        esubcode_o = '0;
        excp_trigger_o = '0;
        tlbehi_update_o = '0;
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
            tlbehi_update_o = '1;
        end else 
        if(excp_i.pif) begin // PIF
            ecode_o = `_ECODE_PIF;
            excp_trigger_o = '1;
            va_error_o = '1;
            tlbehi_update_o = '1;
        end else 
        if(excp_i.ippi) begin // IPPI
            ecode_o = `_ECODE_PPI;
            excp_trigger_o = '1;
            va_error_o = '1;
            tlbehi_update_o = '1;
        end else 
        if(decode_info_i.m2.exception_hint == `_EXCEPTION_HINT_SYSCALL) begin // SYS / BRK
            ecode_o = (decode_info_i.general.inst25_0[16]) ? `_ECODE_SYS : `_ECODE_BRK;
            excp_trigger_o = '1;
        end else 
        if((decode_info_i.m2.exception_hint == `_EXCEPTION_HINT_INVALID) || (decode_info_i.m2.invtlb_en && decode_info_i.general.inst25_0[4:0] > 5'd6)) begin // INE
            ecode_o = `_ECODE_INE;
            excp_trigger_o = '1;
        end else
        if(decode_info_i.m2.priv_inst && (plv_i == 2'd3)) begin // IPE
            ecode_o = `_ECODE_IPE;
            ipe_o = '1;
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
            esubcode_o = `_ESUBCODE_ADEM;
            bad_va_o = vlsu_i;
            va_error_o = '1;
        end else 
        if(trans_en_i && !mmu_resp_i.found && (mem_inst || decode_info_i.m2.cacop)) begin // DTLBR
            ecode_o = `_ECODE_TLBR;
            excp_trigger_o = '1;
            bad_va_o = vlsu_i;
            va_error_o = '1;
            tlbrefill_o = '1;
            tlbehi_update_o = '1;
        end else 
        if(trans_en_i && !mmu_resp_i.v && (mem_inst || decode_info_i.m2.cacop)) begin // PIS / PIL
            ecode_o = decode_info_i.m1.mem_write ? `_ECODE_PIS : `_ECODE_PIL;
            excp_trigger_o = '1;
            bad_va_o = vlsu_i; 
            va_error_o = '1;
            tlbehi_update_o = '1;
        end else
        if(trans_en_i && mmu_resp_i.v && (plv_i > mmu_resp_i.plv) && mem_inst) begin // DPPI
            ecode_o = `_ECODE_PPI;
            excp_trigger_o = '1;
            bad_va_o = vlsu_i;  
            va_error_o = '1;
            tlbehi_update_o = '1;
        end else 
        if(trans_en_i && mmu_resp_i.v && !mmu_resp_i.d && write_inst) begin // PME
            ecode_o = `_ECODE_PME;
            excp_trigger_o = '1;
            bad_va_o = vlsu_i;
            va_error_o = '1;
            tlbehi_update_o = '1;
        end
    end
endmodule
