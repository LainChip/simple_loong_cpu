`include "common.svh"
`include "decoder.svh"
`include "tlb.svh"

`ifdef _TLB_VER_1

module tlb #(
    parameter int TLB_ENTRY_NUM = `TLB_ENTRY_NUM,
    parameter int TLB_PORT = 2
)
(
    input                                       clk         ,
    input                                       rst_n       ,
    //search
    input   tlb_s_req_t     [TLB_PORT - 1 : 0]  s_req_i     ,
    output  tlb_s_resp_t    [TLB_PORT - 1 : 0]  s_resp_o    ,
    //write
    input   tlb_w_req_t                         w_req_i     ,
    //read
    input   [$clog2(`TLB_ENTRY_NUM)-1:0]        r_index_i   ,
    output  tlb_r_resp_t                        r_resp_o    ,
    //invalid
    input   tlb_inv_req_t                       inv_req_i   

);

endmodule : tlb

`endif 