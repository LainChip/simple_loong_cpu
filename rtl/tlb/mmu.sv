`include "tlb.svh"
`include "csr.svh"

module mmu #(
    parameter TLB_ENTRY_NUM = `_TLB_ENTRY_NUM,
    parameter TLB_PORT = `_TLB_PORT
)(
    input                                   clk          ,
    input                                   rst_n        ,
    input                                   mmu_instr_trans_en,
    input               [TLB_PORT - 1 : 0]  mmu_data_trans_en ,
    input  mmu_s_req_t  [TLB_PORT - 1 : 0]  mmu_s_data_req_i  ,
    output mmu_s_resp_t [TLB_PORT - 1 : 0]  mmu_s_data_resp_o ,
    input  mmu_s_req_t                      mmu_s_instr_req_i ,
    output mmu_s_resp_t                     mmu_s_instr_resp_o,

    input decode_info_t                     decode_info_i,
    input [25:0]                            instr_i      ,

    input [ 4:0]                            rand_index_i ,
    input [31:0]                            tlbehi_i     ,
    input [31:0]                            tlbelo0_i    ,
    input [31:0]                            tlbelo1_i    ,
    input [31:0]                            tlbidx_i     ,
    input [31:0]                            ecode_i      ,

    output [31:0]                           tlbehi_o     ,
    output [31:0]                           tlbelo0_o    ,
    output [31:0]                           tlbelo1_o    ,
    output [31:0]                           tlbidx_o     ,
    output [ 9:0]                           asid_o       ,

    input [9:0]                             invtlb_asid  ,
    input [18:0]                            invtlb_vpn   ,

    input [31:0]                            csr_dmw0_i   ,
    input [31:0]                            csr_dmw1_i   ,
    input                                   csr_da_i     ,
    input                                   csr_pg_i
);

tlb_s_req_t [TLB_PORT-1:0]  tlb_s_data_req;
tlb_s_resp_t [TLB_PORT-1:0]  tlb_s_data_resp;
tlb_s_req_t tlb_s_instr_req;
tlb_s_resp_t tlb_s_instr_resp;
tlb_w_req_t tlb_w_req;
logic [4:0]  tlb_r_index;
tlb_r_resp_t tlb_r_resp;
tlb_inv_req_t tlb_inv_req;

logic pg_mode;
logic da_mode;

generate
    for(genvar i = 0; i < TLB_PORT; ++i) begin
        assign tlb_s_data_req[i].vppn     = mmu_s_data_req_i[i].vaddr[31:13];
        assign tlb_s_data_req[i].odd_page = mmu_s_data_req_i[i].vaddr[12];
        assign tlb_s_data_req[i].fetch    = mmu_s_data_req_i[i].fetch;
        assign tlb_s_data_req[i].asid     = mmu_s_data_req_i[i].asid;

        assign tlb_s_data_resp[i].found = mmu_s_data_resp_o[i].found;
        assign tlb_s_data_resp[i].index = mmu_s_data_resp_o[i].index;
        assign tlb_s_data_resp[i].ps    = mmu_s_data_resp_o[i].ps;
        assign tlb_s_data_resp[i].v     = mmu_s_data_resp_o[i].v;
        assign tlb_s_data_resp[i].d     = mmu_s_data_resp_o[i].d;
        assign tlb_s_data_resp[i].mat   = mmu_s_data_resp_o[i].mat;
        assign tlb_s_data_resp[i].plv   = mmu_s_data_resp_o[i].plv;
    end
endgenerate

assign tlb_s_instr_req.vppn = mmu_s_instr_req_i.vaddr[31:13];
assign tlb_s_instr_req.odd_page = mmu_s_instr_req_i.vaddr[12];
assign tlb_s_instr_req.fetch    = mmu_s_instr_req_i.fetch;
assign tlb_s_instr_req.asid     = mmu_s_instr_req_i.asid;

assign tlb_s_instr_resp.found = mmu_s_instr_resp_o.found;
assign tlb_s_instr_resp.index = mmu_s_instr_resp_o.index;
assign tlb_s_instr_resp.ps    = mmu_s_instr_resp_o.ps;
assign tlb_s_instr_resp.v     = mmu_s_instr_resp_o.v;
assign tlb_s_instr_resp.d     = mmu_s_instr_resp_o.d;
assign tlb_s_instr_resp.mat   = mmu_s_instr_resp_o.mat;
assign tlb_s_instr_resp.plv   = mmu_s_instr_resp_o.plv;

assign tlb_w_req.we = decode_info_i.tlbfill_en || decode_info_i.tlbwr_en;
assign tlb_w_req.index = ({5{decode_info_i.tlbfill_en}} & rand_index_i) 
               | ({5{decode_info_i.tlbwr_en}} & tlbidx_i[`_TLBIDX_INDEX]);
assign tlb_w_req.vppn  = tlbehi_i[`_TLBEHI_VPPN];
assign tlb_w_req.g     = tlbelo0_i[`_TLBELO_TLB_G] && tlbelo1_i[`_TLBELO_TLB_G];
assign tlb_w_req.ps    = tlbidx_i[`_TLBIDX_PS];
assign tlb_w_req.e     = (ecode_i == 6'h3f) ? 1'b1 : !tlbidx_i[`_TLBIDX_NE];
assign tlb_w_req.v0    = tlbelo0_i[`_TLBELO_TLB_V];
assign tlb_w_req.d0    = tlbelo0_i[`_TLBELO_TLB_D];
assign tlb_w_req.plv0  = tlbelo0_i[`_TLBELO_TLB_PLV];
assign tlb_w_req.mat0  = tlbelo0_i[`_TLBELO_TLB_MAT];
assign tlb_w_req.ppn0  = tlbelo0_i[`_TLBELO_TLB_PPN_EN];
assign tlb_w_req.v1    = tlbelo1_i[`_TLBELO_TLB_V];
assign tlb_w_req.d1    = tlbelo1_i[`_TLBELO_TLB_D];
assign tlb_w_req.plv1  = tlbelo1_i[`_TLBELO_TLB_PLV];
assign tlb_w_req.mat1  = tlbelo1_i[`_TLBELO_TLB_MAT];
assign tlb_w_req.ppn1  = tlbelo1_i[`_TLBELO_TLB_PPN_EN];

assign tlb_r_index = tlbidx_i[`_TLBIDX_INDEX];
assign tlbehi_o   = {tlb_r_resp.vppn, 13'b0};
assign tlbelo0_o  = {4'b0, tlb_r_resp.ppn0, 1'b0, tlb_r_resp.g, tlb_r_resp.mat0, tlb_r_resp.plv0, tlb_r_resp.d0, tlb_r_resp.v0};
assign tlbelo1_o  = {4'b0, tlb_r_resp.ppn1, 1'b0, tlb_r_resp.g, tlb_r_resp.mat1, tlb_r_resp.plv1, tlb_r_resp.d1, tlb_r_resp.v1};
assign tlbidx_o   = {!tlb_r_resp.e, 1'b0, tlb_r_resp.ps, 24'b0};
assign asid_o     = tlb_r_resp.asid;

assign tlb_inv_req.en = decode_info_i.invtlb_en;
assign tlb_inv_req.op = instr_i[4:0];
assign tlb_inv_req.asid = invtlb_asid;
assign tlb_inv_req.vpn = invtlb_vpn;

assign pg_mode = !csr_da_i && csr_pg_i;
assign da_mode = csr_da_i && !csr_pg_i;

tlb tlb(
    .clk(clk),
    .s_instr_req_i(tlb_s_instr_req),
    .s_instr_resp_o(tlb_s_instr_resp),
    .s_data_req_i(tlb_s_data_req),
    .s_data_resp_o(tlb_s_data_resp),
    .w_req_i(tlb_w_req),
    .r_index_i(tlb_r_index),
    .r_resp_o(tlb_r_resp),
    .inv_req_i(tlb_inv_req)
);

always_comb begin
    mmu_s_instr_resp_o.paddr = mmu_s_instr_req_i.vaddr;
    if(pg_mode && mmu_s_instr_req_i.dmw0_en) begin
        mmu_s_instr_resp_o.paddr = {csr_dmw0_i[`_DMW_PSEG], mmu_s_instr_req_i.vaddr[28:0]};
    end else if(pg_mode && mmu_s_instr_req_i.dmw1_en)begin
        mmu_s_instr_resp_o.paddr = {csr_dmw1_i[`_DMW_PSEG], mmu_s_instr_req_i.vaddr[28:0]};
    end

    if(mmu_instr_trans_en)begin
        if(tlb_s_instr_resp.ps == 6'd12)begin
            mmu_s_instr_resp_o.paddr[31:12] = tlb_s_instr_resp.ppn;
        end else begin
            mmu_s_instr_resp_o.paddr[31:12] = {tlb_s_instr_resp.ppn[19:10], mmu_s_instr_resp_o.paddr[21:12]};
        end
    end

end

generate
    for(genvar i = 0; i < TLB_PORT; ++i) begin
        mmu_s_data_resp_o[i].paddr = mmu_s_data_req_i[i].vaddr;
        if(pg_mode && mmu_s_data_req_i[i].dmw0_en) begin
            mmu_s_data_resp_o[i].paddr = {csr_dmw0_i[`_DMW_PSEG], mmu_s_data_req_i[i].vaddr[28:0]};
        end else if(pg_mode && mmu_s_data_req_i[i].dmw1_en) begin
            mmu_s_data_resp_o[i].paddr = {csr_dmw1_i[`_DMW_PSEG], mmu_s_data_req_i[i].vaddr[28:0]};
        end

        if(mmu_data_trans_en)begin
            if(tlb_s_data_resp.ps == 6'd12)begin
                mmu_s_data_resp_o[i].paddr[31:12] = tlb_s_data_resp[i].ppn;
            end else begin
                mmu_s_data_resp_o[i].paddr[31:12] = {tlb_s_data_resp[i].ppn[19:10], mmu_s_data_resp_o[i].paddr[21:12]};
            end
        end
    end    
endgenerate

endmodule