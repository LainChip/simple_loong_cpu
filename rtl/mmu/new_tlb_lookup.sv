`include "../pipeline/pipeline.svh"

module tlb_lookup_0_stage#(
    parameter int TLB_ENTRY_NUM = 32,
    parameter bit TLB_SUPPORT_4M_PAGE = 0
  )(
    input logic clk,
    input logic rst_n,
    input logic[9:0] asid,
    input tlb_entry_t[TLB_ENTRY_NUM - 1 : 0] entries_i,
    input logic[31:0] vaddr_i,
    output tlb_s_resp_t tlb_s_resp_o
  );

  if(!TLB_SUPPORT_4M_PAGE) begin
    always_comb begin
      tlb_s_resp_o.dmw = 1'b0;
      tlb_s_resp_o.found = 1'b0;
      tlb_s_resp_o.index = '0;
      tlb_s_resp_o.ps = 6'd12;
      for(integer i = 0 ; i < TLB_ENTRY_NUM ; i ++) begin
        if(entries[i].key.e &&
            entries[i].key.vppn == vaddr_i[31:13] &&
            (entries[i].key.g || entries[i].key.asid == asid)) begin
          tlb_s_resp_o.found |= 1'b1;
          tlb_s_resp_o.index |= i[$clog2(TLB_ENTRY_NUM) - 1 : 0];
          tlb_s_resp_o.value |= entries[i].value[vaddr_i[12]];
        end
      end
    end
  end
  else begin
    always_comb begin
      tlb_s_resp_o.dmw = 1'b0;
      tlb_s_resp_o.found = 1'b0;
      tlb_s_resp_o.index = '0;
      tlb_s_resp_o.ps = 6'd0;
      for(integer i = 0 ; i < TLB_ENTRY_NUM ; i ++) begin
        if(entries[i].key.ps == 6'd12) begin
          if(entries[i].key.e &&
              entries[i].key.vppn == vaddr_i[31:13] &&
              (entries[i].key.g || entries[i].key.asid == asid)) begin
            tlb_s_resp_o.found |= 1'b1;
            tlb_s_resp_o.index |= i[$clog2(TLB_ENTRY_NUM) - 1 : 0];
            tlb_s_resp_o.ps |= 6'd12;
            tlb_s_resp_o.value |= entries[i].value[vaddr_i[12]];
          end
        end
        else begin
          if(entries[i].key.e &&
              entries[i].key.vppn[18:10] == vaddr_i[31:23] &&
              (entries[i].key.g || entries[i].key.asid == asid)) begin
            tlb_s_resp_o.found |= 1'b1;
            tlb_s_resp_o.index |= i[$clog2(TLB_ENTRY_NUM) - 1 : 0];
            tlb_s_resp_o.ps |= 6'd22;
            tlb_s_resp_o.value |= entries[i].value[vaddr_i[22]];
          end
        end
      end
    end
  end
endmodule

module tlb_lookup_1_stage#(
    parameter TLB_ENTRY_NUM = 32
  )(
    input logic clk,
    input logic rst_n,

    input tlb_entry_t[TLB_ENTRY_NUM - 1 : 0] entries_i,
    input logic[31:0] vaddr_i,
    output tlb_s_resp_t tlb_s_resp_o
  );

endmodule
