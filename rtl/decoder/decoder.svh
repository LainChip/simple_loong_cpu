`ifndef _DECODE_HEADER
`define _DECODE_HEADER

`define _MEM_TYPE_NONE (3'd0)
`define _MEM_TYPE_WORD (3'd1)
`define _MEM_TYPE_HALF (3'd2)
`define _MEM_TYPE_BYTE (3'd3)
`define _MEM_TYPE_UWORD (3'd5)
`define _MEM_TYPE_UHALF (3'd6)
`define _MEM_TYPE_UBYTE (3'd7)
`define _BRANCH_INVALID (2'b00)
`define _BRANCH_CONDITION (2'b01)
`define _BRANCH_INDIRECT (2'b10)
`define _CMP_E (3'd0)
`define _CMP_NE (3'd1)
`define _CMP_LE (3'd2)
`define _CMP_GT (3'd3)
`define _CMP_LT (3'd4)
`define _CMP_GE (3'd5)
`define _CMP_LTU (3'd6)
`define _CMP_GEU (3'd7)
`define _REG_R0_IMM (2'b11)
`define _REG_R0_RD (2'b10)
`define _REG_R0_RK (2'b01)
`define _REG_R0_NONE (2'b00)
`define _REG_R1_RJ (1'b1)
`define _REG_R1_NONE (1'b0)
`define _REG_W_BL1 (2'b11)
`define _REG_W_RJD (2'b10)
`define _REG_W_RD (2'b01)
`define _REG_W_NONE (2'b00)
`define _IMM_U5 (3'd0)
`define _IMM_U12 (3'd1)
`define _IMM_S12 (3'd2)
`define _IMM_S20 (3'd3)
`define _IMM_S16 (3'd4)
`define _IMM_S21 (3'd5)
`define _ADDR_IMM_S12 (2'd0)
`define _ADDR_IMM_S14 (2'd1)
`define _ADDR_IMM_S16 (2'd2)
`define _ADDR_IMM_S26 (2'd3)
`define _FUSEL_EX_NONE (1'd0)
`define _FUSEL_EX_ALU (1'd1)
`define _FUSEL_M1_NONE (2'd0)
`define _FUSEL_M1_ALU (2'd1)
`define _FUSEL_M1_MEM (2'd2)
`define _FUSEL_M2_NONE (2'd0)
`define _FUSEL_M2_ALU (2'd1)
`define _FUSEL_M2_CSR (2'd2)
`define _FUSEL_M2_MUL (2'd3)
`define _FUSEL_WB_NONE (1'd0)
`define _FUSEL_WB_DIV (1'd1)
`define _ALU_GTYPE_BW (2'd0)
`define _ALU_GTYPE_INT (2'd1)
`define _ALU_GTYPE_LI (2'd1)
`define _ALU_GTYPE_SFT (2'd2)
`define _ALU_GTYPE_CMP (2'd3)
`define _ALU_STYPE_NOR (2'b00)
`define _ALU_STYPE_AND (2'b01)
`define _ALU_STYPE_OR (2'b10)
`define _ALU_STYPE_XOR (2'b11)
`define _ALU_STYPE_ADD (2'b00)
`define _ALU_STYPE_LIEMPTYSLOT (2'b00)
`define _ALU_STYPE_SUB (2'b10)
`define _ALU_STYPE_PCPLUS4 (2'b10)
`define _ALU_STYPE_LUI (2'b01)
`define _ALU_STYPE_INTEMPTYSLOT0 (2'b00)
`define _ALU_STYPE_PCADDUI (2'b11)
`define _ALU_STYPE_INTEMPTYSLOT1 (2'b00)
`define _ALU_STYPE_SRA (2'b00)
`define _ALU_STYPE_SLL (2'b10)
`define _ALU_STYPE_SRL (2'b11)
`define _ALU_STYPE_SLT (2'b00)
`define _ALU_STYPE_SLTU (2'b01)
`define _MUL_TYPE_MULL (2'b00)
`define _MUL_TYPE_MULH (2'b01)
`define _MUL_TYPE_MULHU (2'b10)
`define _DIV_TYPE_DIV (2'b00)
`define _DIV_TYPE_DIVU (2'b01)
`define _DIV_TYPE_MOD (2'b10)
`define _DIV_TYPE_MODU (2'b11)
`define _LINK_TYPE_PCPLUS4 (2'b00)
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
`define _INV_TLB_ALL (4'b1111)
`define _INV_TLB_MASK_G (4'b1000)
`define _INV_TLB_MASK_NG (4'b0100)
`define _INV_TLB_MASK_ASID (4'b0010)
`define _INV_TLB_MASK_VA (4'b0001)
`define _RDCNT_NONE (2'd0)
`define _RDCNT_ID (2'd1)
`define _RDCNT_VLOW (2'd2)
`define _RDCNT_VHIGH (2'd3)

typedef logic[25 : 0] inst25_0_t;
typedef logic[2 : 0] mem_type_t;
typedef logic[0 : 0] mem_write_t;
typedef logic[0 : 0] mem_read_t;
typedef logic[0 : 0] mem_cacop_t;
typedef logic[0 : 0] llsc_inst_t;
typedef logic[0 : 0] ibarrier_t;
typedef logic[0 : 0] dbarrier_t;
typedef logic[1 : 0] branch_type_t;
typedef logic[2 : 0] cmp_type_t;
typedef logic[31 : 0] debug_inst_t;
typedef logic[0 : 0] need_csr_t;
typedef logic[0 : 0] need_mul_t;
typedef logic[0 : 0] need_div_t;
typedef logic[0 : 0] need_lsu_t;
typedef logic[0 : 0] need_bpu_t;
typedef logic[0 : 0] latest_r0_ex_t;
typedef logic[0 : 0] latest_r0_m1_t;
typedef logic[0 : 0] latest_r0_m2_t;
typedef logic[0 : 0] latest_r0_wb_t;
typedef logic[0 : 0] latest_r1_ex_t;
typedef logic[0 : 0] latest_r1_m1_t;
typedef logic[0 : 0] latest_r1_m2_t;
typedef logic[0 : 0] latest_r1_wb_t;
typedef logic[0 : 0] fu_sel_ex_t;
typedef logic[1 : 0] fu_sel_m1_t;
typedef logic[1 : 0] fu_sel_m2_t;
typedef logic[0 : 0] fu_sel_wb_t;
typedef logic[1 : 0] reg_type_r0_t;
typedef logic[0 : 0] reg_type_r1_t;
typedef logic[1 : 0] reg_type_w_t;
typedef logic[2 : 0] imm_type_t;
typedef logic[1 : 0] addr_imm_type_t;
typedef logic[1 : 0] alu_grand_op_t;
typedef logic[1 : 0] alu_op_t;
typedef logic[0 : 0] ertn_inst_t;
typedef logic[0 : 0] priv_inst_t;
typedef logic[0 : 0] refetch_t;
typedef logic[0 : 0] wait_inst_t;
typedef logic[0 : 0] invalid_inst_t;
typedef logic[0 : 0] syscall_inst_t;
typedef logic[0 : 0] break_inst_t;
typedef logic[0 : 0] csr_op_en_t;
typedef logic[0 : 0] tlbsrch_en_t;
typedef logic[0 : 0] tlbrd_en_t;
typedef logic[0 : 0] tlbwr_en_t;
typedef logic[0 : 0] tlbfill_en_t;
typedef logic[0 : 0] invtlb_en_t;

typedef struct packed {
    mem_type_t mem_type;
    mem_write_t mem_write;
    mem_read_t mem_read;
    ibarrier_t ibarrier;
    dbarrier_t dbarrier;
    branch_type_t branch_type;
    cmp_type_t cmp_type;
    latest_r0_m1_t latest_r0_m1;
    latest_r1_m1_t latest_r1_m1;
    fu_sel_m1_t fu_sel_m1;
    ertn_inst_t ertn_inst;
    priv_inst_t priv_inst;
    refetch_t refetch;
    wait_inst_t wait_inst;
    invalid_inst_t invalid_inst;
    syscall_inst_t syscall_inst;
    break_inst_t break_inst;
}m1_t;

typedef struct packed {
    mem_cacop_t mem_cacop;
    llsc_inst_t llsc_inst;
    need_csr_t need_csr;
    need_mul_t need_mul;
    need_div_t need_div;
    need_lsu_t need_lsu;
    need_bpu_t need_bpu;
    latest_r0_m2_t latest_r0_m2;
    latest_r1_m2_t latest_r1_m2;
    fu_sel_m2_t fu_sel_m2;
    fu_sel_wb_t fu_sel_wb;
    alu_grand_op_t alu_grand_op;
    alu_op_t alu_op;
    csr_op_en_t csr_op_en;
    tlbsrch_en_t tlbsrch_en;
    tlbrd_en_t tlbrd_en;
    tlbwr_en_t tlbwr_en;
    tlbfill_en_t tlbfill_en;
    invtlb_en_t invtlb_en;
}m2_t;

typedef struct packed {
    reg_type_r0_t reg_type_r0;
    reg_type_r1_t reg_type_r1;
    reg_type_w_t reg_type_w;
    imm_type_t imm_type;
}is_t;

typedef struct packed {
    latest_r0_ex_t latest_r0_ex;
    latest_r1_ex_t latest_r1_ex;
    fu_sel_ex_t fu_sel_ex;
    addr_imm_type_t addr_imm_type;
}ex_t;

typedef struct packed {
    debug_inst_t debug_inst;
    latest_r0_wb_t latest_r0_wb;
    latest_r1_wb_t latest_r1_wb;
}wb_t;

typedef struct packed {
    inst25_0_t inst25_0;
}general_t;

typedef struct packed {
    m1_t m1;
    m2_t m2;
    is_t is;
    ex_t ex;
    wb_t wb;
    general_t general;
}decode_info_t;

`endif
