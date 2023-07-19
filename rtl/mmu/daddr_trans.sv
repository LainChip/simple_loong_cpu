
`include "../pipeline/pipeline.svh"

module daddr_trans#(
    parameter bit ENABLE_TLB = 1'b0,
    parameter bit SUPPORT_32_PADDR = 1'b0
  )(
    input logic clk,
    input logic rst_n,

    input logic valid_i,
    input logic[31:0] vaddr_i,

    input logic m1_stall_i,
    output logic ready_o,
    output logic[31:0] paddr_o,

    input csr_t csr_i,
    input logic flush_trans_i, // trigger when address translation change.

    input tlb_w_req_t tlb_w_req_i,
    input tlb_inv_req_t tlb_inv_req_i,

    output tlb_s_resp_t tlb_raw_result_o
  );

  if(ENABLE_TLB) begin
    logic[7:0][1:0] valid_table_q;
    logic[7:0][1:0] istlb_table_q;
    tlb_result_q[7:0] table_tmp_q; // 00 invalid, 11 tlb valid, 01 dmw0 hit, 10 dmw1 hit
    logic[7:0][28:12] tlb_vaddr_q;
    tlb_result_q m1_result_q;
    logic m1_tlb_vaddr_miss_q;
    logic valid_q;
    logic istlb_q;
    logic[31:0] vaddr_q; // IN M1

    logic m1_miss;
    always_ff @(posedge clk) begin
      if(!m1_stall_i) begin
        m1_result_q <= table_tmp_q[vaddr_i[31:29]];
        m1_tlb_vaddr_miss_q <= tlb_vaddr_q[vaddr_i[31:29]] != vaddr_i[28:12];
        valid_q <= valid_table_q[vaddr_i[31:29]];
        istlb_q <= istlb_table_q[vaddr_i[31:29]];
        vaddr_q <= vaddr_i;
      end
      else begin

      end
    end

    // miss 逻辑
    assign m1_miss = !valid_q | (istlb_q & m1_tlb_vaddr_miss_q);

    // 输出逻辑
    assign tlb_raw_result_o = m1_result_q;
    assign ready_o = !m1_miss;

    // 重填状态机
    typedef logic[3:0] fast_translation_fsm_t;
    localparam fast_translation_fsm_t TRANS_FSM_NORMAL = 4'b0001;
    localparam fast_translation_fsm_t TRANS_FSM_DMW0 = 4'b0010;
    localparam fast_translation_fsm_t TRANS_FSM_DMW1 = 4'b0100;
    localparam fast_translation_fsm_t TRANS_FSM_TLB = 4'b1000;
    fast_translation_fsm_t fsm_q,fsm;
    always_ff@(posedge clk) begin
      if(!rst_n) begin
        fsm_q <= TRANS_FSM_NORMAL;
      end
      else begin
        fsm_q <= fsm;
      end
    end
    always_comb begin
      fsm = fsm_q;
      if(flush_trans_i) begin
        fsm = TRANS_FSM_DMW0;
      end else begin
        if(fsm_q == TRANS_FSM_DMW1) begin
            
        end
      end
    end

    assign ready_o = !m1_miss;
  end
  else begin
    logic[31:0] paddr;
    logic dmw0_hit, dmw1_hit;
    logic[2:0] dmw_hit_result;
    logic dmw_miss;
    always_comb begin
      dmw0_hit = ((csr_i.dmw0[`PLV0] && csr_i.crmd[`PLV] == 2'd0)
                  || (csr_i.dmw0[`PLV3] && csr_i.crmd[`PLV] == 2'd3))
               && (vaddr_i[31:29] == csr_i.dmw0[`VSEG]);
      dmw1_hit = ((csr_i.dmw1[`PLV0] && csr_i.crmd[`PLV] == 2'd0)
                  || (csr_i.dmw1[`PLV3] && csr_i.crmd[`PLV] == 2'd3))
               && (vaddr_i[31:29] == csr_i.dmw1[`VSEG]);
      dmw_miss = ~(dmw0_hit | dmw1_hit);
      dmw_hit_result = dmw0_hit ? csr_i.dmw0[`PSEG] : csr_i.dmw1[`PSEG];
    end
    if(SUPPORT_32_PADDR) begin
      assign paddr[28:0] = vaddr_i[28:0];
      assign paddr[31:29] = dmw_hit_result;
    end
    else begin
      assign paddr[28:0] = vaddr_i[28:0];
      assign paddr[31:29] = '0;
    end
    always_ff @(posedge clk) begin
      if(!m1_stall_i) begin
        paddr_o <= paddr;
      end
    end
    assign ready_o = 1'b1;
  end
endmodule
