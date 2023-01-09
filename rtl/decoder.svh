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
`define _CSR_DMW0 (14'h180)
`define _CSR_DMW1 (14'h181)
`define _CSR_BRK (14'h100)
`define _CSR_DISABLE_CACHE (14'h101)
`define _RDCNTV_TYPE_NONE (2'd0)
`define _RDCNTV_TYPE_LOW (2'd1)
`define _RDCNTV_TYPE_HIGH (2'd2)
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

typedef logic [25 : 0] inst25_0_t;
typedef logic [1 : 0] rdcntv_type_t;
typedef logic [0 : 0] do_rdcntid_t;
typedef logic [0 : 0] do_csrrd_t;
typedef logic [13 : 0] csr_num_t;
typedef logic [0 : 0] csr_write_en_t;
typedef logic [0 : 0] tlbsrch_en_t;
typedef logic [0 : 0] tlbrd_en_t;
typedef logic [0 : 0] tlbwr_en_t;
typedef logic [0 : 0] tlbfill_en_t;
typedef logic [0 : 0] invtlb_en_t;
typedef logic [2 : 0] mem_type_t;
typedef logic [0 : 0] mem_write_t;
typedef logic [3 : 0] alu_type_t;
typedef logic [2 : 0] opd_type_t;
typedef logic [0 : 0] opd_unsigned_t;

typedef struct packed {
    csr_num_t csr_num;
    csr_write_en_t csr_write_en;
    tlbsrch_en_t tlbsrch_en;
    tlbrd_en_t tlbrd_en;
    mem_write_t mem_write;
}m2_t;

typedef struct packed {
    rdcntv_type_t rdcntv_type;
    do_rdcntid_t do_rdcntid;
    do_csrrd_t do_csrrd;
}wb_t;

typedef struct packed {
    inst25_0_t inst25_0;
}general_t;

typedef struct packed {
    alu_type_t alu_type;
    opd_type_t opd_type;
    opd_unsigned_t opd_unsigned;
}ex_t;

typedef struct packed {
    tlbwr_en_t tlbwr_en;
    tlbfill_en_t tlbfill_en;
    invtlb_en_t invtlb_en;
    mem_type_t mem_type;
}m1_t;

typedef struct packed {
    m2_t m2;
    wb_t wb;
    general_t general;
    ex_t ex;
    m1_t m1;
}decode_info_t;

`endif
