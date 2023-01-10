`include "common.svh"
`include "csr.svh"

`ifdef __CSR_VER_1

module csr(
    input           clk,
    input           rst_n,
    
    input   logic                   stall_i       //输入：流水线暂停
    input   logic   [25:0]          instr_i,           //输入：指令后26位

    //for read
    input   logic   [13:0]          rd_addr_i,         //输入：读csr寄存器编号
    output  logic   [31:0]          rd_data_o,         //输出：读数据
    
    // for write
    input   logic                   csr_write_en_i,    //输入：csr写使能
    input   logic   [13:0]          wr_addr_i,         //输入：写csr寄存器编号
    input   logic   [31:0]          wr_data_i          //输入：写数据
    input   logic   [31:0]          wr_mask_i          //输入：rj寄存器存放的写掩码

    //for interrupt
    input   logic   [8:0]           interrupt_i        //输入：中断信号

    //for exception
    input   logic   [5:0][1:0]      ecode_i            //输入：两条流水线的例外一级码
    input   logic   [8:0][1:0]      esubcode_i         //输入：两条流水线的例外二级码
    input   logic   [1:0]           excp_trigger_i     //输入：发生异常的流水级
    input   logic   [32:0][1:0]     bad_va_i           //输入：地址相关例外出错的虚地址
    input   logic   [32:0][1:0]     instr_pc_i         //输入：指令pc
    input   logic   [1:0]           do_ertn_i          //输入：两条流水线的例外返回
    output  logic                   do_redirect_o      //输出：是否发生跳转
    output  logic   [31:0]          redirect_addr_o    //输出：返回或跳转的地址
    //todo：tlb related exceptions

    // timer
    output  logic  [63:0]  timer_data_o               //输出：定时器值
    output  logic  [31:0]  tid_o                      //输出：定时器id

    //todo: llbit
    //todo: tlb related addr translate

);

logic [31:0]    reg_crmd;
logic [31:0]    reg_prmd;
logic [31:0]    reg_ectl;
logic [31:0]    reg_estat;
logic [31:0]    reg_era;
logic [31:0]    reg_badv;
logic [31:0]    reg_eentry;
logic [31:0]    reg_tlbidx;
logic [31:0]    reg_tlbehi;
logic [31:0]    reg_tlbelo0;
logic [31:0]    reg_tlbelo1;
logic [31:0]    reg_asid;
logic [31:0]    reg_pgdl;
logic [31:0]    reg_pgdh;
logic [31:0]    reg_pgd;
logic [31:0]    reg_cpuid;
logic [31:0]    reg_save0;
logic [31:0]    reg_save1;
logic [31:0]    reg_save2;
logic [31:0]    reg_save3;
logic [31:0]    reg_tid;
logic [31:0]    reg_tcfg;
logic [31:0]    reg_tval;
logic [31:0]    reg_cntc;
logic [31:0]    reg_ticlr;
logic [31:0]    reg_llbctl;
logic [31:0]    reg_tlbrentry;
logic [31:0]    reg_ctag;
logic [31:0]    reg_dmw0;
logic [31:0]    reg_dmw1;
logic [31:0]    reg_brk;
logic [31:0]    reg_disable_cache;


parameter int addr_crmd             = 0;
parameter int addr_prmd             = 1;
parameter int addr_ectl             = 4;
parameter int addr_estat            = 5;
parameter int addr_era              = 6;
parameter int addr_badv             = 7;
parameter int addr_eentry           = 12;
parameter int addr_tlbidx           = 16;
parameter int addr_tlbehi           = 17;
parameter int addr_tlbelo0          = 18;
parameter int addr_tlbelo1          = 19;
parameter int addr_asid             = 24;
parameter int addr_pgdl             = 25;
parameter int addr_pgdh             = 26;
parameter int addr_pgd              = 27;
parameter int addr_cpuid            = 32;
parameter int addr_save0            = 48;
parameter int addr_save1            = 49;
parameter int addr_save2            = 50;
parameter int addr_save3            = 51;
parameter int addr_tid              = 64;
parameter int addr_tcfg             = 65;
parameter int addr_tval             = 66;
parameter int addr_cntc             = 67;
parameter int addr_ticlr            = 68;
parameter int addr_llbctl           = 96;
parameter int addr_tlbrentry        = 136;
parameter int addr_ctag             = 152;
parameter int addr_dmw0             = 384;
parameter int addr_dmw1             = 385;

parameter int addr_brk              = 256;
parameter int addr_disable_cache    = 257;

//Read
logic read_reg_result;
assign rd_data_o = read_reg_result;

always_comb begin
    case (rd_addr_i)
        addr_crmd          : begin
            read_reg_result = reg_crmd;
        end
        addr_prmd          : begin
            read_reg_result = reg_prmd;
        end
        addr_ectl          : begin
            read_reg_result = reg_ectl;
        end
        addr_estat         : begin
            read_reg_result = reg_estat;
        end
        addr_era           : begin
            read_reg_result = reg_era;
        end
        addr_badv          : begin
            read_reg_result = reg_badv;
        end
        addr_eentry        : begin
            read_reg_result = reg_eentry;
        end
        addr_tlbidx        : begin
            read_reg_result = reg_tlbidx;
        end
        addr_tlbehi        : begin
            read_reg_result = reg_tlbehi;
        end
        addr_tlbelo0       : begin
            read_reg_result = reg_tlbelo0;
        end
        addr_tlbelo1       : begin
            read_reg_result = reg_tlbelo1;
        end
        addr_asid          : begin
            read_reg_result = reg_asid;
        end
        addr_pgdl          : begin
            read_reg_result = reg_pgdl;
        end
        addr_pgdh          : begin
            read_reg_result = reg_pgdh;
        end
        addr_pgd           : begin
            read_reg_result = reg_pgd;
        end
        addr_cpuid         : begin
            read_reg_result = reg_cpuid;
        end
        addr_save0         : begin
            read_reg_result = reg_save0;
        end
        addr_save1         : begin
            read_reg_result = reg_save1;
        end
        addr_save2         : begin
            read_reg_result = reg_save2;
        end
        addr_save3         : begin
            read_reg_result = reg_save3;
        end
        addr_tid           : begin
            read_reg_result = reg_tid;
        end
        addr_tcfg          : begin
            read_reg_result = reg_tcfg;
        end
        addr_tval          : begin
            read_reg_result = reg_tval;
        end
        addr_cntc          : begin
            read_reg_result = reg_cntc;
        end
        addr_ticlr         : begin
            read_reg_result = reg_ticlr;
        end
        addr_llbctl        : begin
            read_reg_result = reg_llbctl;
        end
        addr_tlbrentry     : begin  
            read_reg_result = reg_tlbrentry;
        end
        addr_ctag          : begin
            read_reg_result = reg_ctag;
        end
        addr_dmw0          : begin
            read_reg_result = reg_dmw0;
        end
        addr_dmw1          : begin
            read_reg_result = reg_dmw1;
        end

        addr_brk           : begin
            read_reg_result = reg_brk;
        end
        addr_disable_cache : begin
            read_reg_result = reg_disable_cache;
        end
    endcase
end

//write
logic [31:0] wr_data = instr_i[`_INSTR_RJ] == 5'd1 ? wr_data_i : wr_data_i & wr_mask_i;

logic wen_crmd             = csr_write_en_i & (wr_addr_i == addr_crmd) ;
logic wen_prmd             = csr_write_en_i & (wr_addr_i == addr_prmd) ;
logic wen_ectl             = csr_write_en_i & (wr_addr_i == addr_ectl) ;
logic wen_estat            = csr_write_en_i & (wr_addr_i == addr_estat) ;
logic wen_era              = csr_write_en_i & (wr_addr_i == addr_era) ;
logic wen_badv             = csr_write_en_i & (wr_addr_i == addr_badv) ;
logic wen_eentry           = csr_write_en_i & (wr_addr_i == addr_eentry) ;
logic wen_tlbidx           = csr_write_en_i & (wr_addr_i == addr_tlbidx) ;
logic wen_tlbehi           = csr_write_en_i & (wr_addr_i == addr_tlbehi) ;
logic wen_tlbelo0          = csr_write_en_i & (wr_addr_i == addr_tlbelo0) ;
logic wen_tlbelo1          = csr_write_en_i & (wr_addr_i == addr_tlbelo1) ;
logic wen_asid             = csr_write_en_i & (wr_addr_i == addr_asid) ;
logic wen_pgdl             = csr_write_en_i & (wr_addr_i == addr_pgdl) ;
logic wen_pgdh             = csr_write_en_i & (wr_addr_i == addr_pgdh) ;
logic wen_pgd              = csr_write_en_i & (wr_addr_i == addr_pgd) ;
logic wen_cpuid            = csr_write_en_i & (wr_addr_i == addr_cpuid) ;
logic wen_save0            = csr_write_en_i & (wr_addr_i == addr_save0) ;
logic wen_save1            = csr_write_en_i & (wr_addr_i == addr_save1) ;
logic wen_save2            = csr_write_en_i & (wr_addr_i == addr_save2) ;
logic wen_save3            = csr_write_en_i & (wr_addr_i == addr_save3) ;
logic wen_tid              = csr_write_en_i & (wr_addr_i == addr_tid) ;
logic wen_tcfg             = csr_write_en_i & (wr_addr_i == addr_tcfg) ;
logic wen_tval             = csr_write_en_i & (wr_addr_i == addr_tval) ;
logic wen_cntc             = csr_write_en_i & (wr_addr_i == addr_cntc) ;
logic wen_ticlr            = csr_write_en_i & (wr_addr_i == addr_ticlr) ;
logic wen_llbctl           = csr_write_en_i & (wr_addr_i == addr_llbctl) ;
logic wen_tlbrentry        = csr_write_en_i & (wr_addr_i == addr_tlbrentry) ;
logic wen_ctag             = csr_write_en_i & (wr_addr_i == addr_ctag) ;
logic wen_dmw0             = csr_write_en_i & (wr_addr_i == addr_dmw0) ;
logic wen_dmw1             = csr_write_en_i & (wr_addr_i == addr_dmw1) ;

logic wr_data_crmd        ;
logic wr_data_prmd        ;
logic wr_data_ectl        ;
logic wr_data_estat       ;
logic wr_data_era         ;
logic wr_data_badv        ;
logic wr_data_eentry      ;
logic wr_data_tlbidx      ;
logic wr_data_tlbehi      ;
logic wr_data_tlbelo0     ;
logic wr_data_tlbelo1     ;
logic wr_data_asid        ;
logic wr_data_pgdl        ;
logic wr_data_pgdh        ;
logic wr_data_pgd         ;
logic wr_data_cpuid       ;
logic wr_data_save0       ;
logic wr_data_save1       ;
logic wr_data_save2       ;
logic wr_data_save3       ;
logic wr_data_tid         ;
logic wr_data_tcfg        ;
logic wr_data_tval        ;
logic wr_data_cntc        ;
logic wr_data_ticlr       ;
logic wr_data_llbctl      ;
logic wr_data_tlbrentry   ;
logic wr_data_ctag        ;
logic wr_data_dmw0        ;
logic wr_data_dmw1        ;

always_comb begin
    wr_data_crmd       = (wen_crmd       & ~(|do_redirect_o)) ? wr_data : reg_crmd ;
    wr_data_prmd       = (wen_prmd       & ~(|do_redirect_o)) ? wr_data : reg_prmd ;
    wr_data_ectl       = (wen_ectl       & ~(|do_redirect_o)) ? wr_data : reg_ectl ;
    wr_data_estat      = (wen_estat      & ~(|do_redirect_o)) ? wr_data : reg_estat ;
    wr_data_era        = (wen_era        & ~(|do_redirect_o)) ? wr_data : reg_era ;
    wr_data_badv       = (wen_badv       & ~(|do_redirect_o)) ? wr_data : reg_badv;
    wr_data_eentry     = (wen_eentry     & ~(|do_redirect_o)) ? wr_data : reg_eentry ;
    wr_data_tlbidx     = (wen_tlbidx     & ~(|do_redirect_o)) ? wr_data : reg_tlbidx ;
    wr_data_tlbehi     = (wen_tlbehi     & ~(|do_redirect_o)) ? wr_data : reg_tlbehi ;
    wr_data_tlbelo0    = (wen_tlbelo0    & ~(|do_redirect_o)) ? wr_data : reg_tlbelo0 ;
    wr_data_tlbelo1    = (wen_tlbelo1    & ~(|do_redirect_o)) ? wr_data : reg_tlbelo1 ;
    wr_data_asid       = (wen_asid       & ~(|do_redirect_o)) ? wr_data : reg_asid ;
    wr_data_pgdl       = (wen_pgdl       & ~(|do_redirect_o)) ? wr_data : reg_pgdl ;
    wr_data_pgdh       = (wen_pgdh       & ~(|do_redirect_o)) ? wr_data : reg_pgdh ;
    wr_data_pgd        = (wen_pgd        & ~(|do_redirect_o)) ? wr_data : reg_pgd ;
    wr_data_cpuid      = (wen_cpuid      & ~(|do_redirect_o)) ? wr_data : reg_cpuid ;
    wr_data_save0      = (wen_save0      & ~(|do_redirect_o)) ? wr_data : reg_save0 ;
    wr_data_save1      = (wen_save1      & ~(|do_redirect_o)) ? wr_data : reg_save1 ;
    wr_data_save2      = (wen_save2      & ~(|do_redirect_o)) ? wr_data : reg_save2 ;
    wr_data_save3      = (wen_save3      & ~(|do_redirect_o)) ? wr_data : reg_save3 ;
    wr_data_tid        = (wen_tid        & ~(|do_redirect_o)) ? wr_data : reg_tid;
    wr_data_tcfg       = (wen_tcfg       & ~(|do_redirect_o)) ? wr_data : reg_tcfg ;
    wr_data_tval       = (wen_tval       & ~(|do_redirect_o)) ? wr_data : reg_tval ;
    wr_data_cntc       = (wen_cntc       & ~(|do_redirect_o)) ? wr_data : reg_cntc ;
    wr_data_ticlr      = (wen_ticlr      & ~(|do_redirect_o)) ? wr_data : reg_ticlr ;
    wr_data_llbctl     = (wen_llbctl     & ~(|do_redirect_o)) ? wr_data : reg_llbctl ;
    wr_data_tlbrentry  = (wen_tlbrentry  & ~(|do_redirect_o)) ? wr_data : reg_tlbrentry ;
    wr_data_ctag       = (wen_ctag       & ~(|do_redirect_o)) ? wr_data : reg_ctag ;
    wr_data_dmw0       = (wen_dmw0       & ~(|do_redirect_o)) ? wr_data : reg_dmw0 ;
    wr_data_dmw1       = (wen_dmw1       & ~(|do_redirect_o)) ? wr_data : reg_dmw1 ;

end

always_ff @(posedge clk) begin
    if(~rst_n) begin
        reg_crmd        <= 32'd0;
        reg_prmd        <= 32'd0;
        reg_ectl        <= 32'd0;
        reg_estat       <= 32'd0;
        reg_era         <= 32'd0;
        reg_badv        <= 32'd0;
        reg_eentry      <= 32'd0;
        reg_tlbidx      <= 32'd0;
        reg_tlbehi      <= 32'd0;
        reg_tlbelo0     <= 32'd0;
        reg_tlbelo1     <= 32'd0;
        reg_asid        <= 32'd0;
        reg_pgdl        <= 32'd0;
        reg_pgdh        <= 32'd0;
        reg_pgd         <= 32'd0;
        reg_cpuid       <= 32'd0;
        reg_save0       <= 32'd0;
        reg_save1       <= 32'd0;
        reg_save2       <= 32'd0;
        reg_save3       <= 32'd0;
        reg_tid         <= 32'd0;
        reg_tcfg        <= 32'd0;
        reg_tval        <= 32'd0;
        reg_cntc        <= 32'd0;
        reg_ticlr       <= 32'd0;
        reg_llbctl      <= 32'd0;
        reg_tlbrentry   <= 32'd0;
        reg_ctag        <= 32'd0;
        reg_dmw0        <= 32'd0;
        reg_dmw1        <= 32'd0;
    end else begin
        reg_crmd        <= (wr_data_crmd & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_crmd & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_prmd        <= (wr_data_prmd & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_prmd & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_ectl        <= (wr_data_ectl & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_ectl & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_estat       <= (wr_data_estat & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_estat & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_era         <= (wr_data_era & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_era & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_badv        <= (wr_data_badv & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_badv & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_eentry      <= (wr_data_eentry & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_eentry & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_tlbidx      <= (wr_data_tlbidx & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_tlbidx & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_tlbehi      <= (wr_data_tlbehi & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_tlbehi & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_tlbelo0     <= (wr_data_tlbelo0 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_tlbelo0 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_tlbelo1     <= (wr_data_tlbelo1 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_tlbelo1 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_asid        <= (wr_data_asid & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_asid & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_pgdl        <= (wr_data_pgdl & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_pgdl & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_pgdh        <= (wr_data_pgdh & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_pgdh & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_pgd         <= (wr_data_pgd & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_pgd & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_cpuid       <= (wr_data_cpuid & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_cpuid & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_save0       <= (wr_data_save0 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_save0 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_save1       <= (wr_data_save1 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_save1 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_save2       <= (wr_data_save2 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_save2 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_save3       <= (wr_data_save3 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_save3 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_tid         <= (wr_data_tid & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_tid & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_tcfg        <= (wr_data_tcfg & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_tcfg & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_tval        <= (wr_data_tval & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_tval & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_cntc        <= (wr_data_cntc & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_cntc & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_ticlr       <= (wr_data_ticlr & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_ticlr & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_llbctl      <= (wr_data_llbctl & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_llbctl & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_tlbrentry   <= (wr_data_tlbrentry & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_tlbrentry & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_ctag        <= (wr_data_ctag & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_ctag & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_dmw0        <= (wr_data_dmw0 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_dmw0 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_dmw1        <= (wr_data_dmw1 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_dmw1 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
    end
end


endmodule : csr

`endif