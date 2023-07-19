`include "../pipeline/pipeline.svh"
`include "tlb.svh"

/*--JSON--{"module_name":"lsu","module_ver":"3","module_type":"module"}--JSON--*/

module mmu #(
    parameter TLB_ENTRY_NUM = `_TLB_ENTRY_NUM,
    parameter bit LFSR_RAND = 1'b0,

    // DO NOT CHANGE
    parameter INDEX_LEN = $clog2(TLB_ENTRY_NUM)
  )(
    input logic clk,
    input logic rst_n,

    input csr_t csr_i,

    input tlb_op_t tlb_op_i,

    output tlb_w_req_t tlb_w_req_o,
    output tlb_inv_req_t tlb_inv_req_o
  );
  always_comb begin
    tlb_inv_req_o.en = tlb_op_i.invtlb;
    tlb_inv_req_o.op = tlb_op_i.;
  end

endmodule
