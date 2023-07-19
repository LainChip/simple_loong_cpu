`ifndef _TLB_HEADER
`define _TLB_HEADER

`define _TLB_ENTRY_NUM (32)
`define _TLB_PORT (2)

typedef struct packed {  
    logic                                    fetch     ;
    logic  [18:0]                            vppn      ;
    logic                                    odd_page  ;
    logic  [ 9:0]                            asid      ;
} tlb_s_req_t;

typedef struct packed {
    logic                                    found     ;
    logic [$clog2(`_TLB_ENTRY_NUM)-1:0]      index     ;
    logic [ 5:0]                             ps        ;
    logic [19:0]                             ppn       ;
    logic                                    v         ;
    logic                                    d         ;
    logic [ 1:0]                             mat       ;
    logic [ 1:0]                             plv       ;
    
} tlb_s_resp_t;

typedef struct packed {
    logic                                    we        ;
    logic  [$clog2(`_TLB_ENTRY_NUM)-1:0]     index     ;
    logic  [18:0]                            vppn      ;
    logic  [ 9:0]                            asid      ;
    logic                                    g         ;
    logic  [ 5:0]                            ps        ;
    logic                                    e         ;
    logic                                    v0        ;
    logic                                    d0        ;
    logic  [ 1:0]                            mat0      ;
    logic  [ 1:0]                            plv0      ;
    logic  [19:0]                            ppn0      ;
    logic                                    v1        ;
    logic                                    d1        ;
    logic  [ 1:0]                            mat1      ;
    logic  [ 1:0]                            plv1      ;
    logic  [19:0]                            ppn1      ;
    
} tlb_w_req_t;

typedef struct packed {
    logic                                    en        ;
    logic  [ 4:0]                            op        ;
    logic  [ 9:0]                            asid      ;
    logic  [18:0]                            vpn       ;
} tlb_inv_req_t;

typedef struct packed {
    logic  [18:0]                            vppn      ;
    logic  [ 5:0]                            ps        ;
    logic                                    g         ;
    logic [ 9:0]                             asid      ;
    logic                                    e         ;
    logic [19:0]                             ppn0      ;
    logic [ 1:0]                             plv0      ;
    logic [ 1:0]                             mat0      ;        
    logic                                    d0        ;
    logic                                    v0        ;
    logic [19:0]                             ppn1      ;
    logic [ 1:0]                             plv1      ;
    logic [ 1:0]                             mat1      ;        
    logic                                    d1        ;
    logic                                    v1        ;
} tlb_entry_t;

typedef struct packed {
    logic                  trans_en        ;
    logic  [31:0]          vaddr           ;
    logic                  dmw0_en         ;
    logic                  dmw1_en         ;
} mmu_s_req_t;

typedef struct packed {
    logic                                    found     ;
    logic [$clog2(`_TLB_ENTRY_NUM)-1:0]      index     ;
    logic [ 5:0]                             ps        ;
    logic [31:0]                             paddr     ;
    logic                                    v         ;
    logic                                    d         ;
    logic [ 1:0]                             mat       ;
    logic [ 1:0]                             plv       ;

} mmu_s_resp_t;

`endif
