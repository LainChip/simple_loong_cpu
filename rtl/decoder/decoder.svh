`ifndef _DECODE_HEADER
`define _DECODE_HEADER

`define _CSR_CRMD (14'h0)
`define _CSR_PRMD (14'h1)
`define _CSR_ECTL (14'h4)
`define _CSR_ESTAT (14'h5)
`define _CSR_ERA (14'h6)
`define _CSR_BADV (14'h7)
`define _CSR_EENTRY (14'hc)
`define _CSR_TLBIDX (14'h10)
`define _CSR_TLBEHI (14'h11)
`define _CSR_TLBELO0 (14'h12)
`define _CSR_TLBELO1 (14'h13)
`define _CSR_ASID (14'h18)
`define _CSR_PGDL (14'h19)
`define _CSR_PGDH (14'h1a)
`define _CSR_PGD (14'h1b)
`define _CSR_CPUID (14'h20)
`define _CSR_SAVE0 (14'h30)
`define _CSR_SAVE1 (14'h31)
`define _CSR_SAVE2 (14'h32)
`define _CSR_SAVE3 (14'h33)
`define _CSR_TID (14'h40)
`define _CSR_TCFG (14'h41)
`define _CSR_TVAL (14'h42)
`define _CSR_CNTC (14'h43)
`define _CSR_TICLR (14'h44)
`define _CSR_LLBCTL (14'h60)
`define _CSR_TLBRENTRY (14'h88)
`define _CSR_CTAG (14'h98)
`define _CSR_DMW0 (14'h180)
`define _CSR_DMW1 (14'h181)
`define _CSR_BRK (14'h100)
`define _CSR_DISABLE_CACHE (14'h101)
`define _RDCNTV_TYPE_NONE (2'd0)
`define _RDCNTV_TYPE_LOW (2'd1)
`define _RDCNTV_TYPE_HIGH (2'd2)
`define _EXCEPTION_HINT_NONE (2'd0)
`define _EXCEPTION_HINT_SYSCALL (2'd1)
`define _EXCEPTION_HINT_INVALID (2'd2)
`define _BRANCH_INVALID (2'b00)
`define _BRANCH_IMMEDIATE (2'b01)
`define _BRANCH_INDIRECT (2'b10)
`define _BRANCH_CONDITION (2'b11)
`define _CMP_EQL (3'd0)
`define _CMP_NEQ (3'd1)
`define _CMP_LSS (3'd2)
`define _CMP_GER (3'd3)
`define _CMP_LEQ (3'd4)
`define _CMP_GEQ (3'd5)
`define _CMP_LTU (3'd6)
`define _CMP_GEU (3'd7)
`define _MEM_TYPE_NONE (3'd0)
`define _MEM_TYPE_WORD (3'd1)
`define _MEM_TYPE_HALF (3'd2)
`define _MEM_TYPE_BYTE (3'd3)
`define _MEM_TYPE_UWORD (3'd5)
`define _MEM_TYPE_UHALF (3'd6)
`define _MEM_TYPE_UBYTE (3'd7)
`define _ALU_TYPE_NIL (4'd0)
`define _ALU_TYPE_ADD (4'd1)
`define _ALU_TYPE_SUB (4'd2)
`define _ALU_TYPE_SLT (4'd3)
`define _ALU_TYPE_AND (4'd4)
`define _ALU_TYPE_OR (4'd5)
`define _ALU_TYPE_XOR (4'd6)
`define _ALU_TYPE_NOR (4'd7)
`define _ALU_TYPE_SL (4'd8)
`define _ALU_TYPE_SR (4'd9)
`define _ALU_TYPE_MUL (4'd10)
`define _ALU_TYPE_MULH (4'd11)
`define _ALU_TYPE_DIV (4'd12)
`define _ALU_TYPE_MOD (4'd13)
`define _ALU_TYPE_LUI (4'd14)
`define _OPD_REG (3'b000)
`define _OPD_IMM_U5 (3'b001)
`define _OPD_IMM_S12 (3'b010)
`define _OPD_IMM_U12 (3'b011)
`define _OPD_IMM_S20 (3'b100)
`define _REG_TYPE_I (4'd0)
`define _REG_TYPE_RW (4'd1)
`define _REG_TYPE_RRW (4'd2)
`define _REG_TYPE_W (4'd3)
`define _REG_TYPE_RR (4'd4)
`define _REG_TYPE_BL (4'd5)
`define _REG_TYPE_CSRXCHG (4'd6)
`define _REG_TYPE_RDCNTID (4'd7)
`define _REG_TYPE_INVTLB (4'd8)
`define _REG_WB_ALU (3'd0)
`define _REG_WB_BPF (3'd1)
`define _REG_WB_LSU (3'd2)
`define _REG_WB_CSR (3'd3)
`define _REG_WB_MDU (3'd4)
`define _READY_EX (1'b0)
`define _READY_M2 (1'b1)
`define _USE_EX (1'b0)
`define _USE_M2 (1'b1)

typedef logic[25 : 0] inst25_0_t;
typedef logic[1 : 0] rdcntv_type_t;
typedef logic[1 : 0] exception_hint_t;
typedef logic[0 : 0] do_rdcntid_t;
typedef logic[13 : 0] csr_num_t;
typedef logic[0 : 0] csr_write_en_t;
typedef logic[0 : 0] tlbsrch_en_t;
typedef logic[0 : 0] tlbrd_en_t;
typedef logic[0 : 0] tlbwr_en_t;
typedef logic[0 : 0] tlbfill_en_t;
typedef logic[0 : 0] invtlb_en_t;
typedef logic[0 : 0] do_ertn_t;
typedef logic[1 : 0] branch_type_t;
typedef logic[2 : 0] cmp_type_t;
typedef logic[0 : 0] branch_link_t;
typedef logic[2 : 0] mem_type_t;
typedef logic[0 : 0] mem_write_t;
typedef logic[0 : 0] mem_valid_t;
typedef logic[3 : 0] alu_type_t;
typedef logic[2 : 0] opd_type_t;
typedef logic[0 : 0] opd_unsigned_t;
typedef logic[31 : 0] debug_inst_t;
typedef logic[0 : 0] valid_t;
typedef logic[2 : 0] wb_sel_t;
typedef logic[0 : 0] pipe_one_inst_t;
typedef logic[0 : 0] pipe_two_inst_t;
typedef logic[0 : 0] ready_time_t;
typedef logic[1 : 0] use_time_t;
typedef logic[3 : 0] reg_type_t;

typedef struct packed {
    branch_type_t branch_type;
    cmp_type_t cmp_type;
    branch_link_t branch_link;
    alu_type_t alu_type;
    opd_type_t opd_type;
    opd_unsigned_t opd_unsigned;
}ex_t;

typedef struct packed {
    debug_inst_t debug_inst;
    valid_t valid;
    wb_sel_t wb_sel;
}wb_t;

typedef struct packed {
    inst25_0_t inst25_0;
}general_t;

typedef struct packed {
    rdcntv_type_t rdcntv_type;
    exception_hint_t exception_hint;
    do_rdcntid_t do_rdcntid;
    csr_num_t csr_num;
    csr_write_en_t csr_write_en;
    tlbsrch_en_t tlbsrch_en;
    tlbrd_en_t tlbrd_en;
    do_ertn_t do_ertn;
}m2_t;

typedef struct packed {
    pipe_one_inst_t pipe_one_inst;
    pipe_two_inst_t pipe_two_inst;
    ready_time_t ready_time;
    use_time_t use_time;
    reg_type_t reg_type;
}is_t;

typedef struct packed {
    tlbwr_en_t tlbwr_en;
    tlbfill_en_t tlbfill_en;
    invtlb_en_t invtlb_en;
    mem_type_t mem_type;
    mem_write_t mem_write;
    mem_valid_t mem_valid;
}m1_t;

typedef struct packed {
    ex_t ex;
    wb_t wb;
    general_t general;
    m2_t m2;
    is_t is;
    m1_t m1;
}decode_info_t;

`endif
