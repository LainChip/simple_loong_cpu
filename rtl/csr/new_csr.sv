`include "../pipeline/pipeline.svh"
`include "csr.svh"

module la_csr(
    input logic clk,
    input logic rst_n,
    input excp_flow_t excp_i, // M2 EXCPTION IN
    input logic valid_i,
    input logic commit_i,

    input logic m2_stall_i,

    input logic[13:0] csr_r_addr_i, // M1 in
    input logic[1:0] rdcnt_i,
    input logic csr_we_i,
    input logic[13:0] csr_w_addr_i, // M2 in
    input logic[31:0] csr_w_mask_i,
    input logic[31:0] csr_w_data_i,

    output logic[31:0] csr_r_data_o,
    output csr_t csr_o
  );

  //timer_64
  logic[63:0] timer_64_q;
  always_ff @(posedge clk) begin
    if(~rst_n) begin
      timer_64_q <= 64'd0;
    end
    else begin
      timer_64_q <= timer_64_q + 64'b1;
    end
  end

  logic csr_we;
  logic[31:0] csr_w_data;
  assign csr_we = !m2_stall_i && csr_we_i && commit_i && valid_i;
  assign csr_w_data = (csr_r_data_o & ~csr_w_mask_i) | (csr_w_data_i & ~csr_w_mask_i);

  logic crmd_we,crmd_re;
  assign crmd_we = csr_we && (csr_w_addr_i == `_CSR_CRMD);

  // EXCPTION JUDGE OH
  logic excp_int;
  logic excp_pif;
  logic excp_pis;
  logic excp_pme;
  logic excp_ppi;
  logic excp_adef;
  logic excp_adem;
  logic excp_ale;
  logic excp_sys;
  logic excp_brk;
  logic excp_ine;
  logic excp_ipe;
  logic excp_tlbr; // TODO: FIXME

  logic excp_valid; // TODO: FIXME
  logic ertn_valid;
  logic ertn_tlbr_valid;

  logic [31:0] crmd_q;
  logic [31:0] prmd_q;
  logic [31:0] euen_q;
  logic [31:0] ectl_q;
  logic [31:0] estat_q;
  logic [31:0] era_q;
  logic [31:0] badv_q;
  logic [31:0] eentry_q;
  logic [31:0] tlbidx_q;
  logic [31:0] tlbehi_q;
  logic [31:0] tlbelo0_q;
  logic [31:0] tlbelo1_q;
  logic [31:0] asid_q;
  logic [31:0] pgdl_q;
  logic [31:0] pgdh_q;
  logic [31:0] cpuid_q;
  logic [31:0] save0_q;
  logic [31:0] save1_q;
  logic [31:0] save2_q;
  logic [31:0] save3_q;
  logic [31:0] tid_q;
  logic [31:0] tcfg_q;
  logic [31:0] tval_q;
  logic [31:0] cntc_q;
  logic [31:0] ticlr_q;
  logic [31:2] llbctl_q;
  logic [31:0] tlbrentry_q;
  logic [31:0] ctag_q;
  logic [31:0] dmw0_q;
  logic [31:0] dmw1_q;

  always_ff @(posedge clk) begin
    if(!rst_n) begin
      crmd_q[  `_CRMD_PLV] <= 2'b0;
      crmd_q[   `_CRMD_IE] <=  1'b0;
      crmd_q[   `_CRMD_DA] <=  1'b1;
      crmd_q[   `_CRMD_PG] <=  1'b0;
      crmd_q[ `_CRMD_DATF] <=  2'b0;
      crmd_q[ `_CRMD_DATM] <=  2'b0;
      crmd_q[      31 : 9] <= 23'b0;
    end
    else begin
      if(excp_tlbr) begin
        crmd_q[`_CRMD_DA] <= 1'b1;
        crmd_q[`_CRMD_PG] <= 1'b0;
      end
      if(excp_valid) begin
        crmd_q[`_CRMD_PLV] <= 2'b0;
        crmd_q[`_CRMD_IE] <= 1'b0;
      end
      if(ertn_valid) begin
        crmd_q[`_CRMD_PLV] <= prmd_q[`_PRMD_PPLV];
        crmd_q[`_CRMD_IE] <= prmd_q[`_PRMD_PIE];
      end
      if(ertn_tlbr_valid) begin
        crmd_q[`_CRMD_DA] <= 1'b0;
        crmd_q[`_CRMD_PG] <= 1'b1;
      end
      if(crmd_we) begin
        crmd_q[ `_CRMD_PLV] <= csr_w_data[ `_CRMD_PLV];
        crmd_q[  `_CRMD_IE] <= csr_w_data[  `_CRMD_IE];
        crmd_q[  `_CRMD_DA] <= csr_w_data[  `_CRMD_DA];
        crmd_q[  `_CRMD_PG] <= csr_w_data[  `_CRMD_PG];
        crmd_q[`_CRMD_DATF] <= csr_w_data[`_CRMD_DATF];
        crmd_q[`_CRMD_DATM] <= csr_w_data[`_CRMD_DATM];
      end

    end
  end
  assign csr_o.crmd = crmd_q;
  logic prmd_we,prmd_re;
  assign prmd_we = csr_we && (csr_w_addr_i == `_CSR_PRMD);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      prmd_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(prmd_we) begin
        prmd_q <= csr_w_data;
      end
    end
  end
  assign csr_o.prmd = prmd_q;
  logic euen_we,euen_re;
  assign euen_we = csr_we && (csr_w_addr_i == `_CSR_EUEN);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      euen_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(euen_we) begin
        euen_q <= csr_w_data;
      end
    end
  end
  assign csr_o.euen = euen_q;
  logic ectl_we,ectl_re;
  assign ectl_we = csr_we && (csr_w_addr_i == `_CSR_ECTL);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      ectl_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(ectl_we) begin
        ectl_q <= csr_w_data;
      end
    end
  end
  assign csr_o.ectl = ectl_q;
  logic estat_we,estat_re;
  assign estat_we = csr_we && (csr_w_addr_i == `_CSR_ESTAT);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      estat_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(estat_we) begin
        estat_q <= csr_w_data;
      end
    end
  end
  assign csr_o.estat = estat_q;
  logic era_we,era_re;
  assign era_we = csr_we && (csr_w_addr_i == `_CSR_ERA);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      era_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(era_we) begin
        era_q <= csr_w_data;
      end
    end
  end
  assign csr_o.era = era_q;
  logic badv_we,badv_re;
  assign badv_we = csr_we && (csr_w_addr_i == `_CSR_BADV);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      badv_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(badv_we) begin
        badv_q <= csr_w_data;
      end
    end
  end
  assign csr_o.badv = badv_q;
  logic eentry_we,eentry_re;
  assign eentry_we = csr_we && (csr_w_addr_i == `_CSR_EENTRY);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      eentry_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(eentry_we) begin
        eentry_q <= csr_w_data;
      end
    end
  end
  assign csr_o.eentry = eentry_q;
  logic tlbidx_we,tlbidx_re;
  assign tlbidx_we = csr_we && (csr_w_addr_i == `_CSR_TLBIDX);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      tlbidx_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(tlbidx_we) begin
        tlbidx_q <= csr_w_data;
      end
    end
  end
  assign csr_o.tlbidx = tlbidx_q;
  logic tlbehi_we,tlbehi_re;
  assign tlbehi_we = csr_we && (csr_w_addr_i == `_CSR_TLBEHI);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      tlbehi_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(tlbehi_we) begin
        tlbehi_q <= csr_w_data;
      end
    end
  end
  assign csr_o.tlbehi = tlbehi_q;
  logic tlbelo0_we,tlbelo0_re;
  assign tlbelo0_we = csr_we && (csr_w_addr_i == `_CSR_TLBELO0);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      tlbelo0_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(tlbelo0_we) begin
        tlbelo0_q <= csr_w_data;
      end
    end
  end
  assign csr_o.tlbelo0 = tlbelo0_q;
  logic tlbelo1_we,tlbelo1_re;
  assign tlbelo1_we = csr_we && (csr_w_addr_i == `_CSR_TLBELO1);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      tlbelo1_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(tlbelo1_we) begin
        tlbelo1_q <= csr_w_data;
      end
    end
  end
  assign csr_o.tlbelo1 = tlbelo1_q;
  logic asid_we,asid_re;
  assign asid_we = csr_we && (csr_w_addr_i == `_CSR_ASID);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      asid_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(asid_we) begin
        asid_q <= csr_w_data;
      end
    end
  end
  assign csr_o.asid = asid_q;
  logic pgdl_we,pgdl_re;
  assign pgdl_we = csr_we && (csr_w_addr_i == `_CSR_PGDL);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      pgdl_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(pgdl_we) begin
        pgdl_q <= csr_w_data;
      end
    end
  end
  assign csr_o.pgdl = pgdl_q;
  logic pgdh_we,pgdh_re;
  assign pgdh_we = csr_we && (csr_w_addr_i == `_CSR_PGDH);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      pgdh_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(pgdh_we) begin
        pgdh_q <= csr_w_data;
      end
    end
  end
  assign csr_o.pgdh = pgdh_q;
  logic cpuid_we,cpuid_re;
  assign cpuid_we = csr_we && (csr_w_addr_i == `_CSR_CPUID);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      cpuid_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(cpuid_we) begin
        cpuid_q <= csr_w_data;
      end
    end
  end
  assign csr_o.cpuid = cpuid_q;
  logic save0_we,save0_re;
  assign save0_we = csr_we && (csr_w_addr_i == `_CSR_SAVE0);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      save0_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(save0_we) begin
        save0_q <= csr_w_data;
      end
    end
  end
  assign csr_o.save0 = save0_q;
  logic save1_we,save1_re;
  assign save1_we = csr_we && (csr_w_addr_i == `_CSR_SAVE1);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      save1_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(save1_we) begin
        save1_q <= csr_w_data;
      end
    end
  end
  assign csr_o.save1 = save1_q;
  logic save2_we,save2_re;
  assign save2_we = csr_we && (csr_w_addr_i == `_CSR_SAVE2);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      save2_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(save2_we) begin
        save2_q <= csr_w_data;
      end
    end
  end
  assign csr_o.save2 = save2_q;
  logic save3_we,save3_re;
  assign save3_we = csr_we && (csr_w_addr_i == `_CSR_SAVE3);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      save3_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(save3_we) begin
        save3_q <= csr_w_data;
      end
    end
  end
  assign csr_o.save3 = save3_q;
  logic tid_we,tid_re;
  assign tid_we = csr_we && (csr_w_addr_i == `_CSR_TID);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      tid_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(tid_we) begin
        tid_q <= csr_w_data;
      end
    end
  end
  assign csr_o.tid = tid_q;
  logic tcfg_we,tcfg_re;
  assign tcfg_we = csr_we && (csr_w_addr_i == `_CSR_TCFG);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      tcfg_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(tcfg_we) begin
        tcfg_q <= csr_w_data;
      end
    end
  end
  assign csr_o.tcfg = tcfg_q;
  logic tval_we,tval_re;
  assign tval_we = csr_we && (csr_w_addr_i == `_CSR_TVAL);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      tval_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(tval_we) begin
        tval_q <= csr_w_data;
      end
    end
  end
  assign csr_o.tval = tval_q;
  logic cntc_we,cntc_re;
  assign cntc_we = csr_we && (csr_w_addr_i == `_CSR_CNTC);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      cntc_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(cntc_we) begin
        cntc_q <= csr_w_data;
      end
    end
  end
  assign csr_o.cntc = cntc_q;
  logic ticlr_we,ticlr_re;
  assign ticlr_we = csr_we && (csr_w_addr_i == `_CSR_TICLR);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      ticlr_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(ticlr_we) begin
        ticlr_q <= csr_w_data;
      end
    end
  end
  assign csr_o.ticlr = ticlr_q;
  logic llbctl_we,llbctl_re;
  assign llbctl_we = csr_we && (csr_w_addr_i == `_CSR_LLBCTL);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      llbctl_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(llbctl_we) begin
        llbctl_q <= csr_w_data;
      end
    end
  end
  assign csr_o.llbctl = llbctl_q;
  logic tlbrentry_we,tlbrentry_re;
  assign tlbrentry_we = csr_we && (csr_w_addr_i == `_CSR_TLBRENTRY);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      tlbrentry_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(tlbrentry_we) begin
        tlbrentry_q <= csr_w_data;
      end
    end
  end
  assign csr_o.tlbrentry = tlbrentry_q;
  logic ctag_we,ctag_re;
  assign ctag_we = csr_we && (csr_w_addr_i == `_CSR_CTAG);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      ctag_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(ctag_we) begin
        ctag_q <= csr_w_data;
      end
    end
  end
  assign csr_o.ctag = ctag_q;
  logic dmw0_we,dmw0_re;
  assign dmw0_we = csr_we && (csr_w_addr_i == `_CSR_DMW0);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      dmw0_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(dmw0_we) begin
        dmw0_q <= csr_w_data;
      end
    end
  end
  assign csr_o.dmw0 = dmw0_q;
  logic dmw1_we,dmw1_re;
  assign dmw1_we = csr_we && (csr_w_addr_i == `_CSR_DMW1);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      dmw1_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      if(dmw1_we) begin
        dmw1_q <= csr_w_data;
      end
    end
  end
  assign csr_o.dmw1 = dmw1_q;
  logic llbit_q;
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      llbit_q <= /*DEFAULT VALUE*/'0;
    end
    else begin
      // TODO
    end
  end

  // 读取逻辑
  assign crmd_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_CRMD;
  assign prmd_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_PRMD;
  assign euen_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_EUEN;
  assign ectl_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_ECTL;
  assign estat_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_ESTAT;
  assign era_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_ERA;
  assign badv_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_BADV;
  assign eentry_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_EENTRY;
  assign tlbidx_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_TLBIDX;
  assign tlbehi_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_TLBEHI;
  assign tlbelo0_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_TLBELO0;
  assign tlbelo1_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_TLBELO1;
  assign asid_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_ASID;
  assign pgdl_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_PGDL;
  assign pgdh_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_PGDH;
  assign cpuid_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_CPUID;
  assign save0_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_SAVE0;
  assign save1_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_SAVE1;
  assign save2_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_SAVE2;
  assign save3_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_SAVE3;
  assign tid_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_TID;
  assign tcfg_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_TCFG;
  assign tval_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_TVAL;
  assign cntc_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_CNTC;
  assign ticlr_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_TICLR;
  assign llbctl_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_LLBCTL;
  assign tlbrentry_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_TLBRENTRY;
  assign ctag_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_CTAG;
  assign dmw0_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_DMW0;
  assign dmw1_re = rdcnt_i == '0 && csr_r_addr_i[7:0] == `_CSR_DMW1;
  logic cntid_re,cntl_re,cnth_re;
  assign cntid_re = rdcnt_i == `_RDCNT_ID;
  assign cntl_re = rdcnt_i == `_RDCNT_VLOW;
  assign cnth_re = rdcnt_i == `_RDCNT_VHIGH;

  always_ff @(posedge clk) begin
    if(!m2_stall_i) begin
      if(crmd_re) begin
        csr_r_data_o <= crmd_q;
      end
      if(prmd_re) begin
        csr_r_data_o <= prmd_q;
      end
      if(euen_re) begin
        csr_r_data_o <= euen_q;
      end
      if(ectl_re) begin
        csr_r_data_o <= ectl_q;
      end
      if(estat_re) begin
        csr_r_data_o <= estat_q;
      end
      if(era_re) begin
        csr_r_data_o <= era_q;
      end
      if(badv_re) begin
        csr_r_data_o <= badv_q;
      end
      if(eentry_re) begin
        csr_r_data_o <= eentry_q;
      end
      if(tlbidx_re) begin
        csr_r_data_o <= tlbidx_q;
      end
      if(tlbehi_re) begin
        csr_r_data_o <= tlbehi_q;
      end
      if(tlbelo0_re) begin
        csr_r_data_o <= tlbelo0_q;
      end
      if(tlbelo1_re) begin
        csr_r_data_o <= tlbelo1_q;
      end
      if(asid_re) begin
        csr_r_data_o <= asid_q;
      end
      if(pgdl_re) begin
        csr_r_data_o <= pgdl_q;
      end
      if(pgdh_re) begin
        csr_r_data_o <= pgdh_q;
      end
      if(cpuid_re) begin
        csr_r_data_o <= cpuid_q;
      end
      if(save0_re) begin
        csr_r_data_o <= save0_q;
      end
      if(save1_re) begin
        csr_r_data_o <= save1_q;
      end
      if(save2_re) begin
        csr_r_data_o <= save2_q;
      end
      if(save3_re) begin
        csr_r_data_o <= save3_q;
      end
      if(tid_re || cntid_re) begin
        csr_r_data_o <= tid_q;
      end
      if(tcfg_re) begin
        csr_r_data_o <= tcfg_q;
      end
      if(tval_re) begin
        csr_r_data_o <= tval_q;
      end
      if(cntc_re) begin
        csr_r_data_o <= cntc_q;
      end
      if(ticlr_re) begin
        csr_r_data_o <= ticlr_q;
      end
      if(llbctl_re) begin
        csr_r_data_o <= llbctl_q;
      end
      if(tlbrentry_re) begin
        csr_r_data_o <= tlbrentry_q;
      end
      if(ctag_re) begin
        csr_r_data_o <= ctag_q;
      end
      if(dmw0_re) begin
        csr_r_data_o <= dmw0_q;
      end
      if(dmw1_re) begin
        csr_r_data_o <= dmw1_q;
      end
      if(cntl_re) begin
        csr_r_data_o <= timer_64_q[31:0];
      end
      if(cnth_re) begin
        csr_r_data_o <= timer_64_q[63:32];
      end
    end
  end
endmodule
