`include "tlb.svh"
`include "csr.svh"

module mmu #(
    parameter TLB_ENTRY_NUM = `_TLB_ENTRY_NUM,
    parameter TLB_PORT = 2,
    parameter bit LFSR_RAND = 1'b0,
    parameter bit ENABLE_TLB = 1'b1,

    // DO NOT CHANGE
    parameter INDEX_LEN = $clog2(TLB_ENTRY_NUM)
)(
    input                                   clk          ,
    input                                   rst_n        ,
    input                                   inst_valid_i ,
    input logic [TLB_PORT - 1 : 0][1:0]     mmu_raw_mat_i,
    input  mmu_s_req_t  [TLB_PORT - 1 : 0]  mmu_s_req_i  ,
    output mmu_s_resp_t [TLB_PORT - 1 : 0]  mmu_s_resp_o ,

    input decode_info_t                     decode_info_i,

    input [31:0]                            tlbehi_i     ,
    input [31:0]                            tlbelo0_i    ,
    input [31:0]                            tlbelo1_i    ,
    input [31:0]                            tlbidx_i     ,
    input [ 5:0]                            ecode_i      ,

    output tlb_entry_t                      tlb_entry_o  ,

    input [63:0]                            timer_rand   ,

    input [9:0]                             asid         ,
    input [9:0]                             invtlb_asid  ,
    input [18:0]                            invtlb_vpn   ,

    input [31:0]                            csr_dmw0_i   ,
    input [31:0]                            csr_dmw1_i   ,
    input                                   csr_da_i     ,
    input                                   csr_pg_i
);

logic [INDEX_LEN - 1:0] rand_index;
tlb_s_req_t [TLB_PORT-1:0]  tlb_s_req;
tlb_s_resp_t [TLB_PORT-1:0]  tlb_s_resp;
tlb_w_req_t tlb_w_req;
logic [4:0]  tlb_r_index;
tlb_inv_req_t tlb_inv_req;

logic pg_mode;
logic da_mode;

if (LFSR_RAND) begin
    // 使用lfsr生成随机数
    lfsr #(
        .LfsrWidth((8 * INDEX_LEN) >= 64 ? 64 : (8 * INDEX_LEN)),
        .OutWidth(INDEX_LEN)
    ) lfsr (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(tlb_w_req.we),
        .out_o(rand_index)
    );
end else begin
    // 顺序随机数
    // assign rand_index = timer_rand[INDEX_LEN - 1:0];
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            rand_index <= '0;
        end else
        // if(decode_info_i.m2.tlbfill_en & ~stall_i) 
        begin
            rand_index <= rand_index + 1'd1;
        end
    end
end

generate
    for(genvar i = 0; i < TLB_PORT; ++i) begin
        assign tlb_s_req[i].vppn     = mmu_s_req_i[i].vaddr[31:13];
        assign tlb_s_req[i].odd_page = mmu_s_req_i[i].vaddr[12];
        assign tlb_s_req[i].asid     = asid;

        assign mmu_s_resp_o[i].found = tlb_s_resp[i].found;
        assign mmu_s_resp_o[i].index = tlb_s_resp[i].index;
        assign mmu_s_resp_o[i].ps    = tlb_s_resp[i].ps;
        assign mmu_s_resp_o[i].v     = tlb_s_resp[i].v;
        assign mmu_s_resp_o[i].d     = tlb_s_resp[i].d;
        // MAT WILL PASS A MUX BY DMW0 AND DMW1 AND ~TRANS_EN
        // assign mmu_s_resp_o[i].mat   = tlb_s_resp[i].mat;
        assign mmu_s_resp_o[i].plv   = tlb_s_resp[i].plv;
    end
endgenerate

assign tlb_w_req.we = (decode_info_i.m2.tlbfill_en | decode_info_i.m2.tlbwr_en) && inst_valid_i;
assign tlb_w_req.index = ({5{decode_info_i.m2.tlbfill_en}} & rand_index) 
                       | ({5{decode_info_i.m2.tlbwr_en}}   & tlbidx_i[`_TLBIDX_INDEX]);
assign tlb_w_req.vppn  = tlbehi_i[`_TLBEHI_VPPN];
assign tlb_w_req.asid  = asid;
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
// assign tlbehi_o   = {tlb_r_resp.vppn, 13'b0};
// assign tlbelo0_o  = {4'b0, tlb_r_resp.ppn0, 1'b0, tlb_r_resp.g, tlb_r_resp.mat0, tlb_r_resp.plv0, tlb_r_resp.d0, tlb_r_resp.v0};
// assign tlbelo1_o  = {4'b0, tlb_r_resp.ppn1, 1'b0, tlb_r_resp.g, tlb_r_resp.mat1, tlb_r_resp.plv1, tlb_r_resp.d1, tlb_r_resp.v1};
// assign tlbidx_o   = {!tlb_r_resp.e, 1'b0, tlb_r_resp.ps, 24'b0};
// assign asid_o     = tlb_r_resp.asid;

assign tlb_inv_req.en = decode_info_i.m2.invtlb_en && inst_valid_i;
assign tlb_inv_req.op = decode_info_i.general.inst25_0[4:0];
assign tlb_inv_req.asid = invtlb_asid;
assign tlb_inv_req.vpn = invtlb_vpn;

assign pg_mode = !csr_da_i && csr_pg_i;
assign da_mode = csr_da_i && !csr_pg_i;

tlb #(
    .TLB_ENTRY_NUM(TLB_ENTRY_NUM),
    .TLB_PORT(TLB_PORT),
    .ENABLE_TLB(ENABLE_TLB)
)tlb(
    .clk(clk),
    .s_req_i(tlb_s_req),
    .s_resp_o(tlb_s_resp),
    .w_req_i(tlb_w_req),
    .r_index_i(tlb_r_index),
    .r_resp_o(tlb_entry_o),
    .inv_req_i(tlb_inv_req)
);

generate
    always_comb begin
        for(integer i = 0; i < TLB_PORT; i += 1) begin
            mmu_s_resp_o[i].paddr = mmu_s_req_i[i].vaddr;
            mmu_s_resp_o[i].mat   =  tlb_s_resp[i].mat;
            if(pg_mode && mmu_s_req_i[i].dmw0_en) begin
                mmu_s_resp_o[i].paddr = {csr_dmw0_i[`_DMW_PSEG], mmu_s_req_i[i].vaddr[28:0]};
            end else 
            if(pg_mode && mmu_s_req_i[i].dmw1_en) begin
                mmu_s_resp_o[i].paddr = {csr_dmw1_i[`_DMW_PSEG], mmu_s_req_i[i].vaddr[28:0]};
            end else 
            if(pg_mode && mmu_s_req_i[i].trans_en)begin
                if(tlb_s_resp[i].ps == 6'd12)begin
                    mmu_s_resp_o[i].paddr[31:12] = tlb_s_resp[i].ppn;
                end else begin
                    mmu_s_resp_o[i].paddr[31:12] = {tlb_s_resp[i].ppn[19:10], mmu_s_resp_o[i].paddr[21:12]};
                end
            end
        end
    end
endgenerate

`ifdef _DIFFTEST_ENABLE
    logic [INDEX_LEN - 1:0] debug_rand_index;
    always_ff @(posedge clk) begin
        if(tlb_w_req.we) begin
            debug_rand_index <= rand_index;
        end
    end
`endif

endmodule
