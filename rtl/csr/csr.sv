`include "common.svh"
`include "decoder.svh"
`include "csr.svh"


//`ifdef __CSR_VER_1

module csr(
    input           clk,
    input           rst_n,
    
    input   decode_info_t           decode_info_i,     //输入：解码信息
    input   logic                   stall_i,           //输入：流水线暂停
    input   logic   [25:0]          instr_i,           //输入：指令后26位

    //for read
    output  logic   [31:0]          rd_data_o,         //输出：读数据
    
    // for write
    
    input   logic   [31:0]          wr_data_i,          //输入：写数据
    input   logic   [31:0]          wr_mask_i,          //输入：rj寄存器存放的写掩码

    //for interrupt
    input   logic   [8:0]           interrupt_i,        //输入：中断信号

    //for exception
    input   logic   [5:0]           ecode_i,            //输入：两条流水线的例外一级码
    input   logic   [8:0]           esubcode_i,         //输入：两条流水线的例外二级码
    input   logic                   excp_trigger_i,     //输入：是否发生异常
    input   logic   [31:0]          bad_va_i,           //输入：地址相关例外出错的虚地址
    input   logic   [31:0]          instr_pc_i,         //输入：指令pc
    
    output  logic   [1:0]           do_redirect_o,      //输出：是否发生跳转
    output  logic   [31:0]          redirect_addr_o,    //输出：返回或跳转的地址

    input   logic                   excp_tlbrefill_i,   //输入： tlbrefill异常
    //todo：tlb related exceptions

    // timer
    output  logic  [63:0]  timer_data_o,                //输出：定时器值
    output  logic  [31:0]  tid_o                        //输出：定时器id

    //todo: llbit
    //todo: tlb related addr translate

);

// initial begin
//     	$dumpfile("logs/vlt_dump.vcd");
//     	$dumpvars();
// end


logic   [13:0]          rd_addr_i;         //输入：读csr寄存器编号
logic                   csr_write_en_i;     //输入：csr写使能
logic   [13:0]          wr_addr_i;          //输入：写csr寄存器编号
logic                   do_ertn_i;          //输入：例外返回

always_comb begin
    rd_addr_i = instr_i[`_INSTR_CSR_NUM];
    wr_addr_i = instr_i[`_INSTR_CSR_NUM];
    csr_write_en_i = decode_info_i.m2.csr_write_en;
    do_ertn_i = decode_info_i.m2.do_ertn;
end

logic [31:0]    reg_crmd;
logic [31:0]    reg_prmd;
logic [31:0]    reg_euen;
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

logic [63:0]    reg_timer_64;



parameter int ADDR_CRMD             = 0;
parameter int ADDR_PRMD             = 1;
parameter int ADDR_EUEN             = 2;
parameter int ADDR_ECTL             = 4;
parameter int ADDR_ESTAT            = 5;
parameter int ADDR_ERA              = 6;
parameter int ADDR_BADV             = 7;
parameter int ADDR_EENTRY           = 12;
parameter int ADDR_TLBIDX           = 16;
parameter int ADDR_TLBEHI           = 17;
parameter int ADDR_TLBELO0          = 18;
parameter int ADDR_TLBELO1          = 19;
parameter int ADDR_ASID             = 24;
parameter int ADDR_PGDL             = 25;
parameter int ADDR_PGDH             = 26;
parameter int ADDR_PGD              = 27;
parameter int ADDR_CPUID            = 32;
parameter int ADDR_SAVE0            = 48;
parameter int ADDR_SAVE1            = 49;
parameter int ADDR_SAVE2            = 50;
parameter int ADDR_SAVE3            = 51;
parameter int ADDR_TID              = 64;
parameter int ADDR_TCFG             = 65;
parameter int ADDR_TVAL             = 66;
parameter int ADDR_CNTC             = 67;
parameter int ADDR_TICLR            = 68;
parameter int ADDR_LLBCTL           = 96;
parameter int ADDR_TLBRENTRY        = 136;
parameter int ADDR_CTAG             = 152;
parameter int ADDR_DMW0             = 384;
parameter int ADDR_DMW1             = 385;

parameter int ADDR_BRK              = 256;
parameter int ADDR_DISABLE_CACHE    = 257;

//Read
logic [31:0] read_reg_result;
assign rd_data_o = read_reg_result;

always_comb begin
    case (rd_addr_i)
        ADDR_CRMD          : begin
            read_reg_result = reg_crmd;
        end
        ADDR_PRMD          : begin
            read_reg_result = reg_prmd;
        end
        ADDR_EUEN          : begin
            read_reg_result = reg_euen;
        end
        ADDR_ECTL          : begin
            read_reg_result = reg_ectl;
        end
        ADDR_ESTAT         : begin
            read_reg_result = reg_estat;
        end
        ADDR_ERA           : begin
            read_reg_result = reg_era;
        end
        ADDR_BADV          : begin
            read_reg_result = reg_badv;
        end
        ADDR_EENTRY        : begin
            read_reg_result = reg_eentry;
        end
        ADDR_TLBIDX        : begin
            read_reg_result = reg_tlbidx;
        end
        ADDR_TLBEHI        : begin
            read_reg_result = reg_tlbehi;
        end
        ADDR_TLBELO0       : begin
            read_reg_result = reg_tlbelo0;
        end
        ADDR_TLBELO1       : begin
            read_reg_result = reg_tlbelo1;
        end
        ADDR_ASID          : begin
            read_reg_result = reg_asid;
        end
        ADDR_PGDL          : begin
            read_reg_result = reg_pgdl;
        end
        ADDR_PGDH          : begin
            read_reg_result = reg_pgdh;
        end
        ADDR_PGD           : begin
            read_reg_result = reg_pgd;
        end
        ADDR_CPUID         : begin
            read_reg_result = reg_cpuid;
        end
        ADDR_SAVE0         : begin
            read_reg_result = reg_save0;
        end
        ADDR_SAVE1         : begin
            read_reg_result = reg_save1;
        end
        ADDR_SAVE2         : begin
            read_reg_result = reg_save2;
        end
        ADDR_SAVE3         : begin
            read_reg_result = reg_save3;
        end
        ADDR_TID           : begin
            read_reg_result = reg_tid;
        end
        ADDR_TCFG          : begin
            read_reg_result = reg_tcfg;
        end
        ADDR_TVAL          : begin
            read_reg_result = reg_tval;
        end
        ADDR_CNTC          : begin
            read_reg_result = reg_cntc;
        end
        ADDR_TICLR         : begin
            read_reg_result = reg_ticlr;
        end
        ADDR_LLBCTL        : begin
            read_reg_result = reg_llbctl;
        end
        ADDR_TLBRENTRY     : begin  
            read_reg_result = reg_tlbrentry;
        end
        ADDR_CTAG          : begin
            read_reg_result = reg_ctag;
        end
        ADDR_DMW1          : begin
            read_reg_result = reg_dmw0;
        end
        ADDR_DMW1          : begin
            read_reg_result = reg_dmw1;
        end

        ADDR_BRK           : begin
            read_reg_result = reg_brk;
        end
        ADDR_DISABLE_CACHE : begin
            read_reg_result = reg_disable_cache;
        end
    endcase
end

//simple reg write
logic [31:0] wr_data = ( instr_i[`_INSTR_RJ] == 5'd1 || instr_i[`_INSTR_RJ] == 5'd0 ) ? wr_data_i : wr_data_i & wr_mask_i;

logic wen_crmd             = csr_write_en_i & (wr_addr_i == ADDR_CRMD) ;
logic wen_prmd             = csr_write_en_i & (wr_addr_i == ADDR_PRMD) ;
logic wen_euen             = csr_write_en_i & (wr_addr_i == ADDR_EUEN) ;
logic wen_ectl             = csr_write_en_i & (wr_addr_i == ADDR_ECTL) ;
logic wen_estat            = csr_write_en_i & (wr_addr_i == ADDR_ESTAT) ;
logic wen_era              = csr_write_en_i & (wr_addr_i == ADDR_ERA) ;
logic wen_badv             = csr_write_en_i & (wr_addr_i == ADDR_BADV) ;
logic wen_eentry           = csr_write_en_i & (wr_addr_i == ADDR_EENTRY) ;
logic wen_tlbidx           = csr_write_en_i & (wr_addr_i == ADDR_TLBIDX) ;
logic wen_tlbehi           = csr_write_en_i & (wr_addr_i == ADDR_TLBEHI) ;
logic wen_tlbelo0          = csr_write_en_i & (wr_addr_i == ADDR_TLBELO0) ;
logic wen_tlbelo1          = csr_write_en_i & (wr_addr_i == ADDR_TLBELO1) ;
logic wen_asid             = csr_write_en_i & (wr_addr_i == ADDR_ASID) ;
logic wen_pgdl             = csr_write_en_i & (wr_addr_i == ADDR_PGDL) ;
logic wen_pgdh             = csr_write_en_i & (wr_addr_i == ADDR_PGDH) ;
logic wen_pgd              = csr_write_en_i & (wr_addr_i == ADDR_PGD) ;
logic wen_cpuid            = csr_write_en_i & (wr_addr_i == ADDR_CPUID) ;
logic wen_save0            = csr_write_en_i & (wr_addr_i == ADDR_SAVE0) ;
logic wen_save1            = csr_write_en_i & (wr_addr_i == ADDR_SAVE1) ;
logic wen_save2            = csr_write_en_i & (wr_addr_i == ADDR_SAVE2) ;
logic wen_save3            = csr_write_en_i & (wr_addr_i == ADDR_SAVE3) ;
logic wen_tid              = csr_write_en_i & (wr_addr_i == ADDR_TID) ;
logic wen_tcfg             = csr_write_en_i & (wr_addr_i == ADDR_TCFG) ;
logic wen_tval             = csr_write_en_i & (wr_addr_i == ADDR_TVAL) ;
logic wen_cntc             = csr_write_en_i & (wr_addr_i == ADDR_CNTC) ;
logic wen_ticlr            = csr_write_en_i & (wr_addr_i == ADDR_TICLR) ;
logic wen_llbctl           = csr_write_en_i & (wr_addr_i == ADDR_LLBCTL) ;
logic wen_tlbrentry        = csr_write_en_i & (wr_addr_i == ADDR_TLBRENTRY) ;
logic wen_ctag             = csr_write_en_i & (wr_addr_i == ADDR_CTAG) ;
logic wen_dmw0             = csr_write_en_i & (wr_addr_i == ADDR_DMW1) ;
logic wen_dmw1             = csr_write_en_i & (wr_addr_i == ADDR_DMW1) ;

logic wr_data_crmd        ;
logic wr_data_prmd        ;
logic wr_data_euen        ;
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


logic [5:0] ecode_selcted;
logic [8:0] esubcode_selected;
logic [7:0] hard_interrupt;
assign hard_interrupt = interrupt_i[7:0];
logic       timer_interrupt;//to assigin
logic       ipi_interrupt;//to assigin
logic       va_error;//to assign


logic [31:0] target_era;

always_comb begin
    

    wr_data_euen       = (wen_euen       & ~(|do_redirect_o)) ? wr_data : reg_euen ;//todo
    wr_data_ectl       = (wen_ectl       & ~(|do_redirect_o)) ? wr_data : reg_ectl ;
    wr_data_estat      = (wen_estat      & ~(|do_redirect_o)) ? 
                        { 1'd0, esubcode_selected, ecode_selcted, 1'b0, ipi_interrupt, timer_interrupt ,1'b0, hard_interrupt, wr_data[1:0]} : 
                        { 1'd0, esubcode_selected, ecode_selcted, 1'b0, ipi_interrupt, timer_interrupt ,1'b0, hard_interrupt, reg_estat[1:0]};
    wr_data_era        = (wen_era        & ~(|do_redirect_o)) ? wr_data : target_era ;//todo
    
    wr_data_eentry     = (wen_eentry     & ~(|do_redirect_o)) ? wr_data : reg_eentry ;
    wr_data_tlbidx     = (wen_tlbidx     & ~(|do_redirect_o)) ? wr_data : reg_tlbidx ;//todo
    wr_data_tlbehi     = (wen_tlbehi     & ~(|do_redirect_o)) ? wr_data : reg_tlbehi ;//todo
    wr_data_tlbelo0    = (wen_tlbelo0    & ~(|do_redirect_o)) ? wr_data : reg_tlbelo0 ;//todo
    wr_data_tlbelo1    = (wen_tlbelo1    & ~(|do_redirect_o)) ? wr_data : reg_tlbelo1 ;//todo
    wr_data_asid       = (wen_asid       & ~(|do_redirect_o)) ? wr_data : reg_asid ;//todo
    wr_data_pgdl       = (wen_pgdl       & ~(|do_redirect_o)) ? wr_data : reg_pgdl ;//todo
    wr_data_pgdh       = (wen_pgdh       & ~(|do_redirect_o)) ? wr_data : reg_pgdh ;//todo
    wr_data_pgd        = (wen_pgd        & ~(|do_redirect_o)) ? wr_data : reg_pgd ;//todo
    wr_data_cpuid      = (wen_cpuid      & ~(|do_redirect_o)) ? wr_data : reg_cpuid ;
    wr_data_save0      = (wen_save0      & ~(|do_redirect_o)) ? wr_data : reg_save0 ;
    wr_data_save1      = (wen_save1      & ~(|do_redirect_o)) ? wr_data : reg_save1 ;
    wr_data_save2      = (wen_save2      & ~(|do_redirect_o)) ? wr_data : reg_save2 ;
    wr_data_save3      = (wen_save3      & ~(|do_redirect_o)) ? wr_data : reg_save3 ;
    wr_data_tid        = (wen_tid        & ~(|do_redirect_o)) ? wr_data : reg_tid;//todo
    wr_data_tcfg       = (wen_tcfg       & ~(|do_redirect_o)) ? wr_data : reg_tcfg ;//todo
    wr_data_tval       = (wen_tval       & ~(|do_redirect_o)) ? wr_data : reg_tval ;//todo
    wr_data_cntc       = (wen_cntc       & ~(|do_redirect_o)) ? wr_data : reg_cntc ;//todo
    wr_data_ticlr      = (wen_ticlr      & ~(|do_redirect_o)) ? wr_data : reg_ticlr ;//todo
    wr_data_llbctl     = (wen_llbctl     & ~(|do_redirect_o)) ? wr_data : reg_llbctl ;//todo
    wr_data_tlbrentry  = (wen_tlbrentry  & ~(|do_redirect_o)) ? wr_data : reg_tlbrentry ;//todo
    wr_data_ctag       = (wen_ctag       & ~(|do_redirect_o)) ? wr_data : reg_ctag ;//todo
    wr_data_dmw0       = (wen_dmw0       & ~(|do_redirect_o)) ? wr_data : reg_dmw0 ;//todo
    wr_data_dmw1       = (wen_dmw1       & ~(|do_redirect_o)) ? wr_data : reg_dmw1 ;//todo

end

always_ff @(posedge clk) begin
    if(~rst_n) begin
        
        
        reg_euen        <= 32'd0;
        reg_ectl        <= 32'd0;
        reg_estat       <= 32'd0;
        reg_era         <= 32'd0;
        
        reg_eentry      <= 32'd0;
        reg_tlbidx      <= 32'd0;
        reg_tlbehi      <= 32'd0;
        reg_tlbelo0     <= 32'd0;
        reg_tlbelo1     <= 32'd0;
        reg_asid        <= 32'd0;//todo init asidbits
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
        
        
        reg_euen        <= (wr_data_euen & 32'b0000_0000_0000_0000_0000_0000_0000_0001) | (reg_euen & ~32'b0000_0000_0000_0000_0000_0000_0000_0111);
        reg_ectl        <= (wr_data_ectl & 32'b0000_0000_0000_0000_0001_1011_1111_1111) | (reg_ectl & ~32'b0000_0000_0000_0000_0001_1011_1111_1111);
        reg_estat       <= (wr_data_estat & 32'b0111_1111_1111_1111_0001_1011_1111_1111) | (reg_estat & ~32'b0111_1111_1111_1111_0001_1011_1111_1111);
        reg_era         <= (wr_data_era & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_era & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        
        reg_eentry      <= (wr_data_eentry & 32'b1111_1111_1111_1111_1111_1111_1100_0000) | (reg_eentry & ~32'b1111_1111_1111_1111_1111_1111_1100_0000);
        reg_tlbidx      <= (wr_data_tlbidx & 32'b1011_1111_0000_0000_1111_1111_1111_1111) | (reg_tlbidx & ~32'b1011_1111_0000_0000_1111_1111_1111_1111);// tlb size define
        reg_tlbehi      <= (wr_data_tlbehi & 32'b1111_1111_1111_1111_1111_0000_0000_0000) | (reg_tlbehi & ~32'b1111_1111_1111_1111_1111_0000_0000_0000);
        reg_tlbelo0     <= (wr_data_tlbelo0 & 32'b1111_1111_1111_1111_1111_1111_0111_1111) | (reg_tlbelo0 & ~32'b1111_1111_1111_1111_1111_1111_0111_1111);//change with pa len
        reg_tlbelo1     <= (wr_data_tlbelo1 & 32'b1111_1111_1111_1111_1111_1111_0111_1111) | (reg_tlbelo1 & ~32'b1111_1111_1111_1111_1111_1111_0111_1111);//change with pa len
        reg_asid        <= (wr_data_asid & 32'b0000_0000_0000_0000_0000_0011_1111_1111) | (reg_asid & ~32'b0000_0000_0000_0000_0000_0011_1111_1111);
        reg_pgdl        <= (wr_data_pgdl & 32'b1111_1111_1111_1111_1111_0000_0000_0000) | (reg_pgdl & ~32'b1111_1111_1111_1111_1111_0000_0000_0000);
        reg_pgdh        <= (wr_data_pgdh & 32'b1111_1111_1111_1111_1111_0000_0000_0000) | (reg_pgdh & ~32'b1111_1111_1111_1111_1111_0000_0000_0000);
        reg_pgd         <= (wr_data_pgd & 32'b1111_1111_1111_1111_1111_0000_0000_0000) | (reg_pgd & ~32'b1111_1111_1111_1111_1111_0000_0000_0000);
        reg_cpuid       <= (wr_data_cpuid & 32'b0000_0000_0000_0000_0000_0000_0000_0000) | (reg_cpuid & ~32'b0000_0000_0000_0000_0000_0000_0000_0000);
        reg_save0       <= (wr_data_save0 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_save0 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_save1       <= (wr_data_save1 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_save1 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_save2       <= (wr_data_save2 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_save2 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_save3       <= (wr_data_save3 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_save3 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_tid         <= (wr_data_tid & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_tid & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_tcfg        <= (wr_data_tcfg & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_tcfg & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);//change with n?
        reg_tval        <= (wr_data_tval & 32'b0000_0000_0000_0000_0000_0000_0000_0000) | (reg_tval & ~32'b0000_0000_0000_0000_0000_0000_0000_0000);
        reg_cntc        <= (wr_data_cntc & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_cntc & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_ticlr       <= (wr_data_ticlr & 32'b0000_0000_0000_0000_0000_0000_0000_0000) | (reg_ticlr & ~32'b0000_0000_0000_0000_0000_0000_0000_0000); // w1 to read about timer
        reg_llbctl      <= (wr_data_llbctl & 32'b0000_0000_0000_0000_0000_0000_0000_0100) | (reg_llbctl & ~32'b0000_0000_0000_0000_0000_0000_0000_0100);//w1 to read about llbit
        reg_tlbrentry   <= (wr_data_tlbrentry & 32'b1111_1111_1111_1111_1111_1111_1100_0000) | (reg_tlbrentry & ~32'b1111_1111_1111_1111_1111_1111_1100_0000);
        reg_ctag        <= (wr_data_ctag & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_ctag & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);//todo
        reg_dmw0        <= (wr_data_dmw0 & 32'b1110_1110_0000_0000_0000_0000_0011_1001) | (reg_dmw0 & ~32'b1110_1110_0000_0000_0000_0000_0011_1001);
        reg_dmw1        <= (wr_data_dmw1 & 32'b1110_1110_0000_0000_0000_0000_0011_1001) | (reg_dmw1 & ~32'b1110_1110_0000_0000_0000_0000_0011_1001);
    end
end

//difficult reg write

//crmd
always_ff @(posedge clk) begin
    if(~rst_n) begin
        reg_crmd[  `_CRMD_PLV] <= 2'b0;
        reg_crmd[   `_CRMD_IE] <=  1'b0;
        reg_crmd[   `_CRMD_DA] <=  1'b1;
        reg_crmd[   `_CRMD_PG] <=  1'b0;
        reg_crmd[ `_CRMD_DATF] <=  2'b0;
        reg_crmd[ `_CRMD_DATM] <=  2'b0;
        reg_crmd[      31 : 9] <= 23'b0;
    end
    else if((|do_redirect_o)) begin
        reg_crmd[`_CRMD_PLV] <= 2'b0;
        reg_crmd[`_CRMD_IE] <= 1'b0;
        //todo tlbrefill
    end
    else if((|do_ertn_i)) begin
        reg_crmd[`_CRMD_PLV] <= reg_prmd[`_PRMD_PPLV];
        reg_crmd[`_CRMD_IE] <= reg_prmd[`_PRMD_PIE];
        //todo tlbrefill
    end
    else if(wen_crmd) begin
        reg_crmd[ `_CRMD_PLV] <= wr_data[ `_CRMD_PLV];
        reg_crmd[  `_CRMD_IE] <= wr_data[  `_CRMD_IE];
        reg_crmd[  `_CRMD_DA] <= wr_data[  `_CRMD_DA];
        reg_crmd[  `_CRMD_PG] <= wr_data[  `_CRMD_PG];
        reg_crmd[`_CRMD_DATF] <= wr_data[`_CRMD_DATF];
        reg_crmd[`_CRMD_DATM] <= wr_data[`_CRMD_DATM];
    end
end

//prmd
always_ff @(posedge clk) begin
    if (~rst_n) begin
        reg_prmd[31:3] <= 29'b0;
    end
    else if ((|do_redirect_o)) begin
        reg_prmd[`_PRMD_PPLV] <= reg_crmd[`_CRMD_PLV];
        reg_prmd[ `_PRMD_PIE] <= reg_crmd[`_CRMD_IE ];
    end
    else if (wen_prmd) begin
        reg_prmd[`_PRMD_PPLV] <= wr_data[`_PRMD_PPLV];
        reg_prmd[ `_PRMD_PIE] <= wr_data[ `_PRMD_PIE];
    end
end

logic [31:0]    bad_va_selected;
//badv
always_ff @(posedge clk) begin
    if (~rst_n) begin
        reg_badv <= 32'd0;
    end
    else if (wen_badv) begin
        reg_badv <= wr_data;
    end
    else if (va_error) begin
        reg_badv <= bad_va_selected;
    end
end

//timer_64
always_ff @(posedge clk) begin
    if(~rst_n)begin
        reg_timer_64 <= 64'd0;
    end else begin
        reg_timer_64 <= reg_timer_64 + 64'b1;
    end
end

always_comb begin
    tid_o = reg_tid;
    timer_data_o = reg_timer_64 + {{32{reg_cntc[31]}}, reg_cntc};
end

//Exception handling
logic [31:0]    exception_handler;
logic [31:0]    interrupt_handler;
logic [31:0]    tlbrefill_handler;//todo
logic do_interrupt;


always_comb begin
    do_interrupt = (|(reg_estat[`_ESTAT_IS] & reg_ectl[`_ECTL_LIE])) & reg_crmd[`_CRMD_IE];
    do_redirect_o       = 1'b0;
    target_era          = reg_era;
    ecode_selcted       = reg_estat[`_ESTAT_ECODE];
    esubcode_selected   = reg_estat[`_ESTAT_ESUBCODE];
    va_error = 0;
    bad_va_selected = reg_badv;
    exception_handler = reg_eentry;
    interrupt_handler = reg_eentry;
    // redirect_addr_o
    if(do_interrupt) begin
        redirect_addr_o = interrupt_handler;
    end else if (excp_trigger_i)begin
        //todo: tlb exception
        redirect_addr_o = exception_handler;
    end else if (do_ertn_i) begin
        redirect_addr_o = reg_era;
    end else begin
        redirect_addr_o = exception_handler;
    end

    /*  assign:
        ecode_selected
        esubcode_selected
        target_era
        do_redirect_o
        va_error
        bad_va_selected 
    */
    if(do_interrupt) begin
        ecode_selcted = 0;
        esubcode_selected = 0;
        target_era = instr_pc_i;
        do_redirect_o = 1'b1;
    end else if (excp_trigger_i)begin
        ecode_selcted = ecode_i;
        esubcode_selected = esubcode_i;
        target_era = instr_pc_i;
        do_redirect_o = 1'b1;
        if (   ecode_i == `_ECODE_ADEF 
            || ecode_i == `_ECODE_ADEM
            || ecode_i == `_ECODE_ALE
            || ecode_i == `_ECODE_PIL
            || ecode_i == `_ECODE_PIS
            || ecode_i == `_ECODE_PIF
            || ecode_i == `_ECODE_PME
            || ecode_i == `_ECODE_PPI  
        //todo: tlbrefill
        ) begin
            va_error = 1'b1;
            bad_va_selected = bad_va_i;
        end      
    end else if (do_ertn_i) begin
        do_redirect_o = 1'b1;
    end 
    else begin
        do_redirect_o = 1'b0;
    end

end



endmodule : csr

//`endif
