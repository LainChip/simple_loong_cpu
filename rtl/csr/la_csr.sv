`include "common.svh"
`include "decoder.svh"
`include "csr.svh"


//`ifdef __CSR_VER_1

module la_csr(
    input           clk,
    input           rst_n,
    
    input   decode_info_t           decode_info_i,     //输入：解码信息
    
    // FROM EXCP MODULE
    input   logic   [5:0]           ecode_i,            //输入：两条流水线的例外一级码
    input   logic   [8:0]           esubcode_i,         //输入：两条流水线的例外二级码
    input   logic                   excp_trigger_i,     //输入：是否发生异常
    input   logic   [31:0]          bad_va_i,           //输入：地址相关例外出错的虚地址
    // input   logic                   tlbrefill_i,
    // input   logic                   ipe_i,              //输入：当前特权指令无效

    // input   logic                   va_error_i,
    input   excp_flow_t             excp_i,
    
    input   logic                   stall_i,           //输入：流水线暂停
    input   logic   [25:0]          instr_i,           //输入：指令后26位

    //for read
    output  logic   [31:0]          rd_data_o,         //输出：读数据
    
    // for write
    
    input   logic   [31:0]          wr_data_i,          //输入：写数据
    input   logic   [31:0]          wr_mask_i,          //输入：rj寄存器存放的写掩码

    //for interrupt
    input   logic   [7:0]           interrupt_i,        //输入：中断信号
    // input   logic                   not_allowed_int_i,  //LSU已经进入处理状态机，M2指令不可撤回

    //for exception
    input   logic   [31:0]          instr_pc_i,         //输入：指令pc
    
    output  logic                   lsu_clr_hint_o,
    output  logic                   do_redirect_o,      //输出：是否发生跳转
    output  logic   [31:0]          redirect_addr_o,    //输出：返回或跳转的地址
    output  logic                   m2_clr_exclude_self_o,

    // timer
    output  logic  [63:0]  timer_data_o,                //输出：定时器值
    output  logic  [31:0]  tid_o,                       //输出：定时器id

    // TLB
    input tlb_entry_t tlb_entry_i,
    input mmu_s_resp_t mmu_resp_i,

    //todo: llbit
    //todo: tlb related addr translate
    input  logic llbit_set_i,
    input  logic llbit_i,
    output logic llbit_o

    `ifdef _DIFFTEST_ENABLE
    ,input logic delay_csr_i
    `endif
);

// DEBUG 
logic estat_chg;
// logic not_allowed_int; // 从stall中恢复的M2级指令不可以接受中断

// initial begin
//     	$dumpfile("logs/vlt_dump.vcd");
//     	$dumpvars();
// end


logic   [13:0]          rd_addr_i;         //输入：读csr寄存器编号
logic                   csr_write_en_i;     //输入：csr写使能
logic   [13:0]          wr_addr_i;          //输入：写csr寄存器编号 
logic                   ertn_i;          //输入：例外返回
logic                   do_ertn;
logic                   va_error_i;
logic                   tlbrefill_i,tlbehi_update_i,tlbehi_update;
logic                   ipe_i;              //输入：当前特权指令无效

//Exception handling
// logic [31:0]    exception_handler;
// logic [31:0]    interrupt_handler;
// logic [31:0]    tlbrefill_handler;//todo
logic do_interrupt;
logic do_exception,do_tlbrefill,do_ertn_tlbrefill,do_refetch;

always_comb begin
    rd_addr_i = instr_i[`_INSTR_CSR_NUM];
    wr_addr_i = instr_i[`_INSTR_CSR_NUM];
    csr_write_en_i = decode_info_i.m2.csr_write_en & (|instr_i[9:5]);
    ertn_i = decode_info_i.m2.do_ertn;
end

logic [31:0]    reg_crmd;
logic [31:0]    reg_prmd;
logic [31:0]    reg_euen;
logic [31:0]    reg_ectl;
logic [31:0]    reg_estat;
logic [31:0]    reg_era;
logic [31:0]    reg_badv;
(* mark_debug="true" *) logic [31:0]    reg_eentry;
logic [31:0]    reg_tlbidx;
logic [31:0]    reg_tlbehi;
logic [31:0]    reg_tlbelo0;
logic [31:0]    reg_tlbelo1;
logic [31:0]    reg_asid;
logic [31:0]    reg_pgdl;
logic [31:0]    reg_pgdh;
// logic [31:0]    reg_pgd;
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
logic [31:2]    reg_llbctl;
logic llbit;
logic [31:0]    reg_tlbrentry;
logic [31:0]    reg_ctag;
logic [31:0]    reg_dmw0;
logic [31:0]    reg_dmw1;
// logic [31:0]    reg_brk;
// logic [31:0]    reg_disable_cache;

(* mark_debug="true" *) logic [63:0]    reg_timer_64;

localparam ADDR_CRMD  = 14'h0;
localparam ADDR_PRMD  = 14'h1;
localparam ADDR_EUEN  = 14'h2;
localparam ADDR_ECTL  = 14'h4;
localparam ADDR_ESTAT = 14'h5;
localparam ADDR_ERA   = 14'h6;
localparam ADDR_BADV  = 14'h7;
localparam ADDR_EENTRY = 14'hc;
localparam ADDR_TLBIDX= 14'h10;
localparam ADDR_TLBEHI= 14'h11;
localparam ADDR_TLBELO0=14'h12;
localparam ADDR_TLBELO1=14'h13;
localparam ADDR_ASID  = 14'h18;
localparam ADDR_PGDL  = 14'h19;
localparam ADDR_PGDH  = 14'h1a;
localparam ADDR_PGD   = 14'h1b;
localparam ADDR_CPUID = 14'h20;
localparam ADDR_SAVE0 = 14'h30;
localparam ADDR_SAVE1 = 14'h31;
localparam ADDR_SAVE2 = 14'h32;
localparam ADDR_SAVE3 = 14'h33;
localparam ADDR_TID   = 14'h40;
localparam ADDR_TCFG  = 14'h41;
localparam ADDR_TVAL  = 14'h42;
localparam ADDR_CNTC  = 14'h43;
localparam ADDR_TICLR = 14'h44;
localparam ADDR_LLBCTL= 14'h60;
localparam ADDR_TLBRENTRY = 14'h88;
localparam ADDR_CTAG      = 14'd98;
localparam ADDR_BRK   = 14'h100;
localparam ADDR_DISABLE_CACHE = 14'h101;
localparam ADDR_DMW0  = 14'h180;
localparam ADDR_DMW1  = 14'h181;


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
            read_reg_result = reg_badv[31] ? reg_pgdh : reg_pgdl;
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
            read_reg_result = {reg_llbctl,1'b0,llbit};
        end
        ADDR_TLBRENTRY     : begin  
            read_reg_result = reg_tlbrentry;
        end
        ADDR_CTAG          : begin
            read_reg_result = reg_ctag;
        end
        ADDR_DMW0          : begin
            read_reg_result = reg_dmw0;
        end
        ADDR_DMW1          : begin
            read_reg_result = reg_dmw1;
        end

        // ADDR_BRK           : begin
        //     read_reg_result = reg_brk;
        // end
        // ADDR_DISABLE_CACHE : begin
        //     read_reg_result = reg_disable_cache;
        // end
        default: begin
            read_reg_result = '0;
        end
    endcase
    if(decode_info_i.is.reg_type == `_REG_TYPE_RDCNTID) begin
        if(decode_info_i.general.inst25_0[4:0] == '0)begin
            read_reg_result = tid_o;
        end else if(decode_info_i.general.inst25_0[10]) begin
            read_reg_result = timer_data_o[63:32];
        end else begin
            read_reg_result = timer_data_o[31:0];
        end
    end
end

//simple reg write
(* mark_debug="true" *) logic [31:0] wr_data;
assign wr_data = ( instr_i[`_INSTR_RJ] == 5'd1 || instr_i[`_INSTR_RJ] == 5'd0 ) ? wr_data_i : ((wr_data_i & wr_mask_i) | (read_reg_result & ~wr_mask_i));
(* mark_debug="true" *) logic write_en;

assign write_en = (~stall_i) & decode_info_i.wb.valid & csr_write_en_i & ~do_exception & ~do_interrupt;

wire wen_crmd             = write_en & (wr_addr_i == ADDR_CRMD) ;
wire wen_prmd             = write_en & (wr_addr_i == ADDR_PRMD) ;
wire wen_euen             = write_en & (wr_addr_i == ADDR_EUEN) ;
wire wen_ectl             = write_en & (wr_addr_i == ADDR_ECTL) ;
wire wen_estat            = write_en & (wr_addr_i == ADDR_ESTAT) ;
wire wen_era              = write_en & (wr_addr_i == ADDR_ERA) ;
wire wen_badv             = write_en & (wr_addr_i == ADDR_BADV) ;
wire wen_eentry           = write_en & (wr_addr_i == ADDR_EENTRY) ;
wire wen_tlbidx           = write_en & (wr_addr_i == ADDR_TLBIDX) ;
wire wen_tlbehi           = write_en & (wr_addr_i == ADDR_TLBEHI) ;
wire wen_tlbelo0          = write_en & (wr_addr_i == ADDR_TLBELO0) ;
wire wen_tlbelo1          = write_en & (wr_addr_i == ADDR_TLBELO1) ;
wire wen_asid             = write_en & (wr_addr_i == ADDR_ASID) ;
wire wen_pgdl             = write_en & (wr_addr_i == ADDR_PGDL) ;
wire wen_pgdh             = write_en & (wr_addr_i == ADDR_PGDH) ;
wire wen_pgd              = write_en & (wr_addr_i == ADDR_PGD) ;
wire wen_cpuid            = write_en & (wr_addr_i == ADDR_CPUID) ;
wire wen_save0            = write_en & (wr_addr_i == ADDR_SAVE0) ;
wire wen_save1            = write_en & (wr_addr_i == ADDR_SAVE1) ;
wire wen_save2            = write_en & (wr_addr_i == ADDR_SAVE2) ;
wire wen_save3            = write_en & (wr_addr_i == ADDR_SAVE3) ;
wire wen_tid              = write_en & (wr_addr_i == ADDR_TID) ;
wire wen_tcfg             = write_en & (wr_addr_i == ADDR_TCFG) ;
wire wen_tval             = write_en & (wr_addr_i == ADDR_TVAL) ;
wire wen_cntc             = write_en & (wr_addr_i == ADDR_CNTC) ;
wire wen_ticlr            = write_en & (wr_addr_i == ADDR_TICLR) ;
wire wen_llbctl           = write_en & (wr_addr_i == ADDR_LLBCTL) ;
wire wen_tlbrentry        = write_en & (wr_addr_i == ADDR_TLBRENTRY) ;
wire wen_ctag             = write_en & (wr_addr_i == ADDR_CTAG) ;
wire wen_dmw0             = write_en & (wr_addr_i == ADDR_DMW0) ;
wire wen_dmw1             = write_en & (wr_addr_i == ADDR_DMW1) ;

logic[31:0] wr_data_crmd        ;
logic[31:0] wr_data_prmd        ;
logic[31:0] wr_data_euen        ;
logic[31:0] wr_data_ectl        ;
logic[31:0] wr_data_estat       ;
logic[31:0] wr_data_era         ;
logic[31:0] wr_data_badv        ;
logic[31:0] wr_data_eentry      ;
logic[31:0] wr_data_tlbidx      ;
logic[31:0] wr_data_tlbehi      ;
logic[31:0] wr_data_tlbelo0     ;
logic[31:0] wr_data_tlbelo1     ;
logic[31:0] wr_data_asid        ;
logic[31:0] wr_data_pgdl        ;
logic[31:0] wr_data_pgdh        ;
logic[31:0] wr_data_pgd         ;
logic[31:0] wr_data_cpuid       ;
logic[31:0] wr_data_save0       ;
logic[31:0] wr_data_save1       ;
logic[31:0] wr_data_save2       ;
logic[31:0] wr_data_save3       ;
logic[31:0] wr_data_tid         ;
logic[31:0] wr_data_tcfg        ;
logic[31:0] wr_data_tval        ;
logic[31:0] wr_data_cntc        ;
logic[31:0] wr_data_ticlr       ;
// logic[31:0] wr_data_llbctl      ;
logic[31:0] wr_data_tlbrentry   ;
logic[31:0] wr_data_ctag        ;
logic[31:0] wr_data_dmw0        ;
logic[31:0] wr_data_dmw1        ;


logic [5:0] ecode_selcted;
logic [8:0] esubcode_selected;
logic       timer_interrupt;//to assign
logic       ipi_interrupt;//to assign
logic       va_error;


logic [31:0] target_era;

always_comb begin
    

    wr_data_euen       = (wen_euen) ? wr_data : reg_euen ;//todo
    wr_data_ectl       = (wen_ectl) ? wr_data : reg_ectl ;
    wr_data_era        = (wen_era) ? wr_data : target_era;//todo
    
    wr_data_eentry     = (wen_eentry) ? wr_data : reg_eentry ;
    wr_data_pgdl       = (wen_pgdl ) ? wr_data : reg_pgdl ;//todo
    wr_data_pgdh       = (wen_pgdh ) ? wr_data : reg_pgdh ;//todo
    // wr_data_pgd        = (wen_pgd  ) ? wr_data : reg_pgd ;//todo
    wr_data_cpuid      = (wen_cpuid ) ? wr_data : reg_cpuid ;
    wr_data_save0      = (wen_save0 ) ? wr_data : reg_save0 ;
    wr_data_save1      = (wen_save1 ) ? wr_data : reg_save1 ;
    wr_data_save2      = (wen_save2 ) ? wr_data : reg_save2 ;
    wr_data_save3      = (wen_save3 ) ? wr_data : reg_save3 ;
    wr_data_tid        = (wen_tid  ) ? wr_data : reg_tid;//todo
    wr_data_tcfg       = (wen_tcfg ) ? wr_data : reg_tcfg ;//todo
    wr_data_cntc       = (wen_cntc ) ? wr_data : reg_cntc ;//todo
    wr_data_ticlr      = (wen_ticlr ) ? wr_data : reg_ticlr ;//todo
    // wr_data_llbctl     = (wen_llbctl) ? wr_data : reg_llbctl ;//todo
    wr_data_tlbrentry  = (wen_tlbrentry) ? wr_data : reg_tlbrentry ;//todo
    wr_data_ctag       = (wen_ctag ) ? wr_data : reg_ctag ;//todo
    wr_data_dmw0       = (wen_dmw0 ) ? wr_data : reg_dmw0 ;//todo
    wr_data_dmw1       = (wen_dmw1 ) ? wr_data : reg_dmw1 ;//todo

end

always_ff @(posedge clk) begin
    if(~rst_n) begin
        
        
        reg_euen        <= 32'd0;
        reg_ectl        <= 32'd0;
        //reg_estat       <= 32'd0;
        reg_era         <= 32'd0;
        
        reg_eentry      <= 32'd0;
        // reg_tlbidx      <= 32'd0;
        // reg_tlbehi      <= 32'd0;
        // reg_tlbelo0     <= 32'd0;
        // reg_tlbelo1     <= 32'd0;
        // reg_asid        <= 32'd0;//todo init asidbits
        reg_pgdl        <= 32'd0;
        reg_pgdh        <= 32'd0;
        // reg_pgd         <= 32'd0;
        reg_cpuid       <= 32'd0;
        reg_save0       <= 32'd0;
        reg_save1       <= 32'd0;
        reg_save2       <= 32'd0;
        reg_save3       <= 32'd0;
        reg_tid         <= 32'd0;
        reg_tcfg        <= 32'd0;
        // reg_tval        <= 32'd0;
        reg_cntc        <= 32'd0;
        reg_ticlr       <= 32'd0;
        // reg_llbctl      <= 32'd0;
        reg_tlbrentry   <= 32'd0;
        reg_ctag        <= 32'd0;
        reg_dmw0        <= 32'd0;
        reg_dmw1        <= 32'd0;
    end else begin
        
        
        reg_euen        <= (wr_data_euen & 32'b0000_0000_0000_0000_0000_0000_0000_0001) | (reg_euen & ~32'b0000_0000_0000_0000_0000_0000_0000_0111);
        reg_ectl        <= (wr_data_ectl & 32'b0000_0000_0000_0000_0001_1011_1111_1111) | (reg_ectl & ~32'b0000_0000_0000_0000_0001_1011_1111_1111);
        reg_era         <= (wr_data_era & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_era & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        
        reg_eentry      <= (wr_data_eentry & 32'b1111_1111_1111_1111_1111_1111_1100_0000) | (reg_eentry & ~32'b1111_1111_1111_1111_1111_1111_1100_0000);
        reg_pgdl        <= (wr_data_pgdl & 32'b1111_1111_1111_1111_1111_0000_0000_0000) | (reg_pgdl & ~32'b1111_1111_1111_1111_1111_0000_0000_0000);
        reg_pgdh        <= (wr_data_pgdh & 32'b1111_1111_1111_1111_1111_0000_0000_0000) | (reg_pgdh & ~32'b1111_1111_1111_1111_1111_0000_0000_0000);
        // reg_pgd         <= (wr_data_pgd & 32'b1111_1111_1111_1111_1111_0000_0000_0000) | (reg_pgd & ~32'b1111_1111_1111_1111_1111_0000_0000_0000);
        reg_cpuid       <= (wr_data_cpuid & 32'b0000_0000_0000_0000_0000_0000_0000_0000) | (reg_cpuid & ~32'b0000_0000_0000_0000_0000_0000_0000_0000);
        reg_save0       <= (wr_data_save0 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_save0 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_save1       <= (wr_data_save1 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_save1 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_save2       <= (wr_data_save2 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_save2 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_save3       <= (wr_data_save3 & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_save3 & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_tid         <= (wr_data_tid & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_tid & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_tcfg        <= (wr_data_tcfg & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_tcfg & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);//change with n?
        reg_cntc        <= (wr_data_cntc & 32'b1111_1111_1111_1111_1111_1111_1111_1111) | (reg_cntc & ~32'b1111_1111_1111_1111_1111_1111_1111_1111);
        reg_ticlr       <= (wr_data_ticlr & 32'b0000_0000_0000_0000_0000_0000_0000_0000) | (reg_ticlr & ~32'b0000_0000_0000_0000_0000_0000_0000_0000); // w1 to read about timer
        // reg_llbctl      <= (wr_data_llbctl & 32'b0000_0000_0000_0000_0000_0000_0000_0100) | (reg_llbctl & ~32'b0000_0000_0000_0000_0000_0000_0000_0100);//w1 to read about llbit
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
    else if(do_exception | do_interrupt) begin
        reg_crmd[`_CRMD_PLV] <= 2'b0;
        reg_crmd[`_CRMD_IE] <= 1'b0;
        if(do_tlbrefill) begin
            reg_crmd[`_CRMD_DA] <= 1'b1;
            reg_crmd[`_CRMD_PG] <= 1'b0;
        end
    end
    else if(do_ertn) begin
        reg_crmd[`_CRMD_PLV] <= reg_prmd[`_PRMD_PPLV];
        reg_crmd[`_CRMD_IE] <= reg_prmd[`_PRMD_PIE];
        //todo tlbrefill
        if(do_ertn_tlbrefill) begin
            reg_crmd[`_CRMD_DA] <= 1'b0;
            reg_crmd[`_CRMD_PG] <= 1'b1;
        end
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
    else if (do_exception | do_interrupt) begin
        reg_prmd[`_PRMD_PPLV] <= reg_crmd[`_CRMD_PLV];
        reg_prmd[ `_PRMD_PIE] <= reg_crmd[`_CRMD_IE ];
    end
    else if (wen_prmd) begin
        reg_prmd[`_PRMD_PPLV] <= wr_data[`_PRMD_PPLV];
        reg_prmd[ `_PRMD_PIE] <= wr_data[ `_PRMD_PIE];
    end
end

//estat
logic timer_en;
always_ff @(posedge clk) begin
    if (~rst_n) begin
        reg_estat <= '0;
        timer_en <= 1'b0;
        estat_chg <= '0;
    end
    else begin
        if (wen_ticlr && wr_data[`_TICLR_CLR]) begin
            reg_estat[11] <= 1'b0;
            estat_chg <= '1;
        end
        else if (wen_tcfg) begin
            timer_en <= wr_data[`_TCFG_EN];
        end
        else if (timer_en && (reg_tval == 32'd0) && ~stall_i) begin
            reg_estat[11] <= 1'b1;
            estat_chg <= '1;
            timer_en      <= reg_tcfg[`_TCFG_PERIODIC];
        end
        else if (do_interrupt | do_exception) begin
            reg_estat[`_ESTAT_ECODE] <= ecode_selcted;
            reg_estat[`_ESTAT_ESUBCODE] <= esubcode_selected;
            estat_chg <= '1;
        end
        else if (wen_estat) begin
            reg_estat[      1:0] <= wr_data[      1:0];
            estat_chg <= '1;
        end else begin
            estat_chg <= '0;
        end

        if(~stall_i) begin
            reg_estat[9:2] <= interrupt_i;
        end
    end

end

//badv
logic [31:0]    bad_va_selected;

always_ff @(posedge clk) begin
    if (~rst_n) begin
        reg_badv <= 32'd0;
    end
    else if (wen_badv) begin
        reg_badv <= wr_data;
    end
    else if (va_error && do_exception) begin
        reg_badv <= bad_va_selected;
    end
end

//tval
always_ff @(posedge clk) begin
    if(wen_tcfg) begin
        reg_tval <= {wr_data[`_TCFG_INITVAL], 2'b0};
    end else if(timer_en) begin
        if(reg_tval != 32'd0)begin
            reg_tval <= reg_tval - 32'd1;
        end else if(reg_tval == 32'b0 && ~stall_i) begin
            reg_tval <= reg_tcfg[`_TCFG_PERIODIC] ? {reg_tcfg[`_TCFG_INITVAL], 2'b0} : 32'hffffffff;
        end
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

//tlbidx
always_ff @(posedge clk) begin
    if (~rst_n) begin
        reg_tlbidx[23: 5] <= 19'b0;
        reg_tlbidx[30]    <= 1'b0;
    end
    else if (wen_tlbidx) begin
        reg_tlbidx[`_TLBIDX_INDEX] <= wr_data[`_TLBIDX_INDEX];
        reg_tlbidx[`_TLBIDX_PS]    <= wr_data[`_TLBIDX_PS];
        reg_tlbidx[`_TLBIDX_NE]    <= wr_data[`_TLBIDX_NE];
    end
    else if (decode_info_i.m2.tlbsrch_en && ~(do_exception || do_interrupt) && ~stall_i && decode_info_i.wb.valid) begin
        if (mmu_resp_i.found) begin
            reg_tlbidx[`_TLBIDX_INDEX] <= mmu_resp_i.index;
            reg_tlbidx[`_TLBIDX_NE]    <= 1'b0;
        end
        else begin
            reg_tlbidx[`_TLBIDX_NE] <= 1'b1;
        end
    end
    else if (decode_info_i.m2.tlbrd_en && tlb_entry_i.e && ~(do_exception || do_interrupt) && ~stall_i && decode_info_i.wb.valid) begin
        reg_tlbidx[`_TLBIDX_PS] <= tlb_entry_i.ps;
        reg_tlbidx[`_TLBIDX_NE] <= ~tlb_entry_i.e;
    end
    else if (decode_info_i.m2.tlbrd_en && ~tlb_entry_i.e && ~(do_exception || do_interrupt) && ~stall_i && decode_info_i.wb.valid) begin
        reg_tlbidx[`_TLBIDX_PS] <= 6'b0;
        reg_tlbidx[`_TLBIDX_NE] <= ~tlb_entry_i.e;
    end
end

//tlbehi
always_ff @(posedge clk) begin
    if (~rst_n) begin
        reg_tlbehi[12:0] <= 13'b0;
    end
    else if (wen_tlbehi) begin
        reg_tlbehi[`_TLBEHI_VPPN] <= wr_data[`_TLBEHI_VPPN];
    end
    else if (decode_info_i.m2.tlbrd_en && tlb_entry_i.e && ~(do_exception || do_interrupt) && ~stall_i && decode_info_i.wb.valid) begin
        reg_tlbehi[`_TLBEHI_VPPN] <= tlb_entry_i.vppn;
    end
    else if (decode_info_i.m2.tlbrd_en && ~tlb_entry_i.e && ~(do_exception || do_interrupt) && ~stall_i && decode_info_i.wb.valid) begin
        reg_tlbehi[`_TLBEHI_VPPN] <= 19'b0;
    end
    else if (tlbehi_update && do_exception) begin
        reg_tlbehi[`_TLBEHI_VPPN] <= bad_va_i[`_TLBEHI_VPPN];
    end
end

//tlbelo0
always_ff @(posedge clk) begin
    if (~rst_n) begin
        reg_tlbelo0[7] <= 1'b0;
        reg_tlbelo0[31:28] <= '0;
    end
    else if (wen_tlbelo0) begin
        reg_tlbelo0[`_TLBELO_TLB_V]   <= wr_data[`_TLBELO_TLB_V];
        reg_tlbelo0[`_TLBELO_TLB_D]   <= wr_data[`_TLBELO_TLB_D];
        reg_tlbelo0[`_TLBELO_TLB_PLV] <= wr_data[`_TLBELO_TLB_PLV];
        reg_tlbelo0[`_TLBELO_TLB_MAT] <= wr_data[`_TLBELO_TLB_MAT];
        reg_tlbelo0[`_TLBELO_TLB_G]   <= wr_data[`_TLBELO_TLB_G];
        reg_tlbelo0[`_TLBELO_TLB_PPN_EN] <= wr_data[`_TLBELO_TLB_PPN_EN];
    end
    else if (decode_info_i.m2.tlbrd_en && tlb_entry_i.e && ~(do_exception || do_interrupt) && ~stall_i && decode_info_i.wb.valid) begin
        reg_tlbelo0[`_TLBELO_TLB_V]   <= tlb_entry_i.v0;
        reg_tlbelo0[`_TLBELO_TLB_D]   <= tlb_entry_i.d0;
        reg_tlbelo0[`_TLBELO_TLB_PLV] <= tlb_entry_i.plv0;
        reg_tlbelo0[`_TLBELO_TLB_MAT] <= tlb_entry_i.mat0;
        reg_tlbelo0[`_TLBELO_TLB_G]   <= tlb_entry_i.g;
        reg_tlbelo0[`_TLBELO_TLB_PPN] <= {4'b0000,tlb_entry_i.ppn0};
    end
    else if (decode_info_i.m2.tlbrd_en && ~tlb_entry_i.e && ~(do_exception || do_interrupt) && ~stall_i && decode_info_i.wb.valid) begin
        reg_tlbelo0[`_TLBELO_TLB_V]   <= 1'b0;
        reg_tlbelo0[`_TLBELO_TLB_D]   <= 1'b0;
        reg_tlbelo0[`_TLBELO_TLB_PLV] <= 2'b0;
        reg_tlbelo0[`_TLBELO_TLB_MAT] <= 2'b0;
        reg_tlbelo0[`_TLBELO_TLB_G]   <= 1'b0;
        reg_tlbelo0[`_TLBELO_TLB_PPN] <= 24'b0;
    end
end

//tlbelo1
always_ff @(posedge clk) begin
    if (~rst_n) begin
        reg_tlbelo1[7] <= 1'b0;
    end
    else if (wen_tlbelo1) begin
        reg_tlbelo1[`_TLBELO_TLB_V]      <= wr_data[`_TLBELO_TLB_V];
        reg_tlbelo1[`_TLBELO_TLB_D]      <= wr_data[`_TLBELO_TLB_D];
        reg_tlbelo1[`_TLBELO_TLB_PLV]    <= wr_data[`_TLBELO_TLB_PLV];
        reg_tlbelo1[`_TLBELO_TLB_MAT]    <= wr_data[`_TLBELO_TLB_MAT];
        reg_tlbelo1[`_TLBELO_TLB_G]      <= wr_data[`_TLBELO_TLB_G];
        reg_tlbelo1[`_TLBELO_TLB_PPN_EN] <= wr_data[`_TLBELO_TLB_PPN_EN];
    end
    else if (decode_info_i.m2.tlbrd_en && tlb_entry_i.e && ~(do_exception || do_interrupt) && ~stall_i && decode_info_i.wb.valid) begin
        reg_tlbelo1[`_TLBELO_TLB_V]   <= tlb_entry_i.v1;
        reg_tlbelo1[`_TLBELO_TLB_D]   <= tlb_entry_i.d1;
        reg_tlbelo1[`_TLBELO_TLB_PLV] <= tlb_entry_i.plv1;
        reg_tlbelo1[`_TLBELO_TLB_MAT] <= tlb_entry_i.mat1;
        reg_tlbelo1[`_TLBELO_TLB_G]   <= tlb_entry_i.g;
        reg_tlbelo1[`_TLBELO_TLB_PPN] <= {4'b0000,tlb_entry_i.ppn1};
    end
    else if (decode_info_i.m2.tlbrd_en && ~tlb_entry_i.e && ~(do_exception || do_interrupt) && ~stall_i && decode_info_i.wb.valid) begin
        reg_tlbelo1[`_TLBELO_TLB_V]   <= 1'b0;
        reg_tlbelo1[`_TLBELO_TLB_D]   <= 1'b0;
        reg_tlbelo1[`_TLBELO_TLB_PLV] <= 2'b0;
        reg_tlbelo1[`_TLBELO_TLB_MAT] <= 2'b0;
        reg_tlbelo1[`_TLBELO_TLB_G]   <= 1'b0;
        reg_tlbelo1[`_TLBELO_TLB_PPN] <= 24'b0;
    end
end

//asid
always_ff @(posedge clk) begin
    if (~rst_n) begin
        reg_asid[31:10] <= 22'h280; //ASIDBITS = 10
    end
    else if (wen_asid) begin
        reg_asid[`_ASID] <= wr_data[`_ASID];
    end
    else if (decode_info_i.m2.tlbrd_en && tlb_entry_i.e && ~(do_exception || do_interrupt) && ~stall_i && decode_info_i.wb.valid) begin
        reg_asid[`_ASID] <= tlb_entry_i.asid;
    end
    else if (decode_info_i.m2.tlbrd_en && ~tlb_entry_i.e && ~(do_exception || do_interrupt) && ~stall_i && decode_info_i.wb.valid) begin
        reg_asid[`_ASID] <= 10'b0;
    end
end

//llbctl
always_ff @(posedge clk) begin
    if(~rst_n) begin
        reg_llbctl[`_LLBCT_KLO] <= 1'b0;
        reg_llbctl[31:3] <= 29'b0;
        llbit <= '0;
    end 
    else if(do_ertn) begin
        if(reg_llbctl[`_LLBCT_KLO]) begin
            reg_llbctl[`_LLBCT_KLO] <= 1'b0;
        end else begin
            llbit <= '0;
        end
    end
    else if(wen_llbctl) begin
        reg_llbctl[`_LLBCT_KLO] <= wr_data[`_LLBCT_KLO];
        if (wr_data[`_LLBCT_WCLLB] == 1'b1) begin
            llbit <= 1'b0;
        end
    end
    else if(llbit_set_i && ~stall_i && ~lsu_clr_hint_o && ~(do_exception || do_interrupt) && decode_info_i.wb.valid) begin
        llbit <= llbit_i;
    end
end
assign llbit_o = llbit;

always_comb begin
    tid_o = reg_tid;
    timer_data_o = reg_timer_64 + {{32{reg_cntc[31]}}, reg_cntc};
end

logic interrupt_need_handle;
assign interrupt_need_handle = (|(reg_estat[`_ESTAT_IS] & reg_ectl[`_ECTL_LIE])) & reg_crmd[`_CRMD_IE];
always_comb begin
    tlbehi_update = '0;
    do_refetch = '0;
    do_tlbrefill = '0;
    do_ertn_tlbrefill = reg_estat[`_ESTAT_ECODE] == 6'h3f;
    lsu_clr_hint_o = 1'b0;
    do_ertn = 1'b0;
    do_interrupt        = 1'b0;
    do_redirect_o       = 1'b0;
    do_exception        = 1'b0;
    target_era          = reg_era;
    ecode_selcted       = reg_estat[`_ESTAT_ECODE];
    esubcode_selected   = reg_estat[`_ESTAT_ESUBCODE];
    va_error = 0;
    bad_va_selected = reg_badv;
    // exception_handler = reg_eentry;
    // interrupt_handler = reg_eentry;
    // tlbrefill_handler = reg_tlbrentry;
    redirect_addr_o = reg_eentry;
    // redirect_addr_o
    if(interrupt_need_handle/* && !not_allowed_int*/) begin
        redirect_addr_o = reg_eentry;
        lsu_clr_hint_o = 1'b1;
    end else if (excp_trigger_i)begin
        //todo: tlb exception
        redirect_addr_o = reg_eentry;
        lsu_clr_hint_o = 1'b1;
        if(tlbrefill_i) begin
            redirect_addr_o = reg_tlbrentry;
        end
    end else if (ertn_i) begin
        redirect_addr_o = reg_era;
    end else begin
        redirect_addr_o = reg_eentry;
    end

    /*  assign:
        ecode_selected
        esubcode_selected
        target_era
        do_redirect_o
        va_error
        bad_va_selected 
    */
    if(interrupt_need_handle && (~stall_i) && decode_info_i.wb.valid/* && !not_allowed_int*/) begin
        ecode_selcted = '0;
        esubcode_selected = '0;
        target_era = instr_pc_i;
        do_redirect_o = 1'b1;
        do_interrupt  = 1'b1;
    end else if (excp_trigger_i & (~stall_i) & decode_info_i.wb.valid)begin
        ecode_selcted = ecode_i;
        esubcode_selected = esubcode_i;
        target_era = instr_pc_i;
        do_redirect_o = 1'b1;
        do_exception  = 1'b1;
        tlbehi_update = tlbehi_update_i;
        if (
            //    ecode_i == `_ECODE_ADEF 
            // || ecode_i == `_ECODE_ADEM
            // || ecode_i == `_ECODE_ALE
            // || ecode_i == `_ECODE_PIL
            // || ecode_i == `_ECODE_PIS
            // || ecode_i == `_ECODE_PIF
            // || ecode_i == `_ECODE_PME
            // || ecode_i == `_ECODE_PPI  
            va_error_i
        //todo: tlbrefill
        ) begin
            va_error = 1'b1;
            bad_va_selected = bad_va_i;
        end
        if(tlbrefill_i) begin
            do_tlbrefill = '1;
        end
    end else if (ertn_i & (~stall_i) & decode_info_i.wb.valid) begin
        do_redirect_o = 1'b1;
        do_ertn = 1'b1;
    end else if(decode_info_i.m2.refetch && (~stall_i) && decode_info_i.wb.valid) begin
        do_redirect_o = 1'b1;
        do_refetch = 1'b1;
        redirect_addr_o = instr_pc_i + 32'd4;
    end else begin
        do_redirect_o = 1'b0;
    end
end

// assign m2_clr_exclude_self_o = (m2_ctrl_flow.decode_info.m2.do_ertn == 1'b1) || (m2_ctrl_flow.decode_info.m2.exception_hint == `_EXCEPTION_HINT_SYSCALL) || (m2_ctrl_flow.decode_info.m2.exception_hint == `_EXCEPTION_HINT_INVALID && ~excp_i.adef);
assign m2_clr_exclude_self_o = do_ertn || do_refetch;

// WAIT LOGIC
logic wait_valid,int_valid;
assign wait_valid = decode_info_i.m2.wait_hint && ~(do_exception || do_interrupt) && ~stall_i && decode_info_i.wb.valid;
assign int_valid = (|(reg_ectl[`_ECTL_LIE] & reg_estat[`_ESTAT_IS])) & reg_crmd[`_CRMD_IE];

// always_ff @(posedge clk) begin
//     not_allowed_int <= stall_i;
// end

`ifdef _DIFFTEST_ENABLE

logic [31:0] delay_reg_crmd;
always_ff @(posedge clk) begin
    delay_reg_crmd <= reg_crmd;
end
logic [31:0] delay_reg_prmd;
always_ff @(posedge clk) begin
    delay_reg_prmd <= reg_prmd;
end
logic [31:0] delay_reg_euen;
always_ff @(posedge clk) begin
    delay_reg_euen <= reg_euen;
end
logic [31:0] delay_reg_ectl;
always_ff @(posedge clk) begin
    delay_reg_ectl <= reg_ectl;
end
logic [31:0] delay_reg_estat;
always_ff @(posedge clk) begin
    delay_reg_estat <= reg_estat;
end
logic [31:0] delay_reg_era;
always_ff @(posedge clk) begin
    delay_reg_era <= reg_era;
end
logic [31:0] delay_reg_badv;
always_ff @(posedge clk) begin
    delay_reg_badv <= reg_badv;
end
logic [31:0] delay_reg_eentry;
always_ff @(posedge clk) begin
    delay_reg_eentry <= reg_eentry;
end
logic [31:0] delay_reg_tlbidx;
always_ff @(posedge clk) begin
    delay_reg_tlbidx <= reg_tlbidx;
end
logic [31:0] delay_reg_tlbehi;
always_ff @(posedge clk) begin
    delay_reg_tlbehi <= reg_tlbehi;
end
logic [31:0] delay_reg_tlbelo0;
always_ff @(posedge clk) begin
    delay_reg_tlbelo0 <= reg_tlbelo0;
end
logic [31:0] delay_reg_tlbelo1;
always_ff @(posedge clk) begin
    delay_reg_tlbelo1 <= reg_tlbelo1;
end
logic [31:0] delay_reg_asid;
always_ff @(posedge clk) begin
    delay_reg_asid <= reg_asid;
end
logic [31:0] delay_reg_pgdl;
always_ff @(posedge clk) begin
    delay_reg_pgdl <= reg_pgdl;
end
logic [31:0] delay_reg_pgdh;
always_ff @(posedge clk) begin
    delay_reg_pgdh <= reg_pgdh;
end
logic [31:0] delay_reg_save0;
always_ff @(posedge clk) begin
    delay_reg_save0 <= reg_save0;
end
logic [31:0] delay_reg_save1;
always_ff @(posedge clk) begin
    delay_reg_save1 <= reg_save1;
end
logic [31:0] delay_reg_save2;
always_ff @(posedge clk) begin
    delay_reg_save2 <= reg_save2;
end
logic [31:0] delay_reg_save3;
always_ff @(posedge clk) begin
    delay_reg_save3 <= reg_save3;
end
logic [31:0] delay_reg_tid;
always_ff @(posedge clk) begin
    delay_reg_tid <= reg_tid;
end
logic [31:0] delay_reg_tcfg;
always_ff @(posedge clk) begin
    delay_reg_tcfg <= reg_tcfg;
end
logic [31:0] delay_reg_tval;
always_ff @(posedge clk) begin
    delay_reg_tval <= reg_tval;
end
logic [31:0] delay_reg_ticlr;
always_ff @(posedge clk) begin
    delay_reg_ticlr <= reg_ticlr;
end
logic [31:0] delay_reg_llbctl;
always_ff @(posedge clk) begin
    delay_reg_llbctl <= {reg_llbctl,1'b0,llbit};
end
logic [31:0] delay_reg_tlbrentry;
always_ff @(posedge clk) begin
    delay_reg_tlbrentry <= reg_tlbrentry;
end
logic [31:0] delay_reg_dmw0;
always_ff @(posedge clk) begin
    delay_reg_dmw0 <= reg_dmw0;
end
logic [31:0] delay_reg_dmw1;
always_ff @(posedge clk) begin
    delay_reg_dmw1 <= reg_dmw1;
end

DifftestCSRRegState DifftestCSRRegState(
    .clock              (clk               ),
    .coreid             (0                  ),
    .crmd               (delay_csr_i ? delay_reg_crmd : reg_crmd),
    .prmd               (delay_csr_i ? delay_reg_prmd : reg_prmd),
    .euen               (delay_csr_i ? delay_reg_euen : reg_euen),
    .ecfg               (delay_csr_i ? delay_reg_ectl : reg_ectl),
    .estat              (delay_csr_i ? delay_reg_estat : reg_estat),
    .era                (delay_csr_i ? delay_reg_era : reg_era),
    .badv               (delay_csr_i ? delay_reg_badv : reg_badv),
    .eentry             (delay_csr_i ? delay_reg_eentry : reg_eentry),
    .tlbidx             (delay_csr_i ? delay_reg_tlbidx : reg_tlbidx),
    .tlbehi             (delay_csr_i ? delay_reg_tlbehi : reg_tlbehi),
    .tlbelo0            (delay_csr_i ? delay_reg_tlbelo0 : reg_tlbelo0),
    .tlbelo1            (delay_csr_i ? delay_reg_tlbelo1 : reg_tlbelo1),
    .asid               (delay_csr_i ? delay_reg_asid : reg_asid),
    .pgdl               (delay_csr_i ? delay_reg_pgdl : reg_pgdl),
    .pgdh               (delay_csr_i ? delay_reg_pgdh : reg_pgdh),
    .save0              (delay_csr_i ? delay_reg_save0 : reg_save0),
    .save1              (delay_csr_i ? delay_reg_save1 : reg_save1),
    .save2              (delay_csr_i ? delay_reg_save2 : reg_save2),
    .save3              (delay_csr_i ? delay_reg_save3 : reg_save3),
    .tid                (delay_csr_i ? delay_reg_tid : reg_tid),
    .tcfg               (delay_csr_i ? delay_reg_tcfg : reg_tcfg),
    .tval               (delay_csr_i ? delay_reg_tval : reg_tval),
    .ticlr              (delay_csr_i ? delay_reg_ticlr : reg_ticlr),
    .llbctl             (delay_csr_i ? delay_reg_llbctl : {reg_llbctl,1'b0,llbit}),
    .tlbrentry          (delay_csr_i ? delay_reg_tlbrentry : reg_tlbrentry),
    .dmw0               (delay_csr_i ? delay_reg_dmw0 : reg_dmw0),
    .dmw1               (delay_csr_i ? delay_reg_dmw1 : reg_dmw1)
);

logic[31:0] debug_pc_r,debug_pc_r_1,debug_inst_r,debug_inst_r_1;
logic debug_exception_r,debug_exception_r_1,debug_ertn_r,debug_ertn_r_1;
always_ff @(posedge clk) begin
    debug_pc_r <= instr_pc_i;
    debug_inst_r <= decode_info_i.wb.debug_inst;
    debug_exception_r <= do_exception & do_redirect_o;
    debug_ertn_r <= do_ertn;
    // debug_pc_r_1 <= instr_pc_i;
    // debug_inst_r_1 <= decode_info_i.wb.debug_inst;
    // debug_exception_r_1 <= do_exception & do_redirect_o;
    // debug_ertn_r_1 <= do_ertn;
    // debug_pc_r <= debug_pc_r_1;
    // debug_inst_r <= debug_inst_r_1;
    // debug_exception_r <= debug_exception_r_1;
    // debug_ertn_r <= debug_ertn_r_1;
end
// always_comb begin
//     debug_pc_r = instr_pc_i;
//     debug_inst_r = decode_info_i.wb.debug_inst;
//     debug_exception_r = do_interrupt;
//     debug_ertn_r = do_ertn;
// end

DifftestExcpEvent DifftestExcpEvent(
    .clock              (clk           ),
    .coreid             (0              ),
    .excp_valid         (debug_exception_r),
    // .excp_valid         ('0),
    .eret               (debug_ertn_r),
    // .eret               ('0),
    .intrNo             (reg_estat[12:2]),
    .cause              (reg_estat[`_ESTAT_ECODE]),
    .exceptionPC        (debug_pc_r),
    .exceptionInst      (debug_inst_r)
);

`endif

endmodule : la_csr

//`endif
