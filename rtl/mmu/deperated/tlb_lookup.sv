`include "tlb.svh"

/*--JSON--{"module_name":"deperated","module_ver":"3","module_type":"module"}--JSON--*/
module tlb_lookup#(
    parameter int TLB_ENTRY_NUM = `_TLB_ENTRY_NUM
)(
    input tlb_entry_t [TLB_ENTRY_NUM - 1 : 0] tlb_entry_i,
    input tlb_s_req_t req_i,
    output tlb_s_resp_t resp_o
);

logic [$clog2(TLB_ENTRY_NUM) - 1 :0] matched_index;
logic [TLB_ENTRY_NUM - 1 : 0] matched;
tlb_entry_t matched_entry;

// assign matched_entry = tlb_entry_i[matched_index];
assign resp_o.found = (|matched);
assign resp_o.index = matched_index;

always_comb begin
    // resp_o.ps = '0;
    // resp_o.ppn = '0;
    // resp_o.v = '0;
    // resp_o.d = '0;
    // resp_o.mat = '0;
    // resp_o.plv = '0;
    // if(req_i.fetch) begin
        if((matched_entry.ps == 6'd12) ? 
            req_i.odd_page :
            req_i.vppn[8] ) begin
            resp_o.ps   = matched_entry.ps;
            resp_o.ppn  = matched_entry.ppn1;
            resp_o.v    = matched_entry.v1;
            resp_o.d    = matched_entry.d1;
            resp_o.mat  = matched_entry.mat1;
            resp_o.plv  = matched_entry.plv1;
        end else begin
            resp_o.ps   = matched_entry.ps;
            resp_o.ppn  = matched_entry.ppn0;
            resp_o.v    = matched_entry.v0;
            resp_o.d    = matched_entry.d0;
            resp_o.mat  = matched_entry.mat0;
            resp_o.plv  = matched_entry.plv0;
        end
    // end
end

for (genvar i = 0; i < TLB_ENTRY_NUM; i = i + 1) begin
    assign matched[i] = ((tlb_entry_i[i].ps == 6'd12) ? 
                        (req_i.vppn == tlb_entry_i[i].vppn) :
                        (req_i.vppn[18:9] == tlb_entry_i[i].vppn[18:9]))
                        && (tlb_entry_i[i].asid == req_i.asid || tlb_entry_i[i].g)
                        && (tlb_entry_i[i].e == 1'b1);
end

always_comb begin
    matched_index = '0;
    matched_entry = matched[0] ? tlb_entry_i[0] : '0;
    for(int i = 1; i < TLB_ENTRY_NUM; i = i + 1) begin
        if(matched[i]) begin
            matched_index |= i[$clog2(TLB_ENTRY_NUM) - 1 :0];
            matched_entry |= tlb_entry_i[i];
        end
    end
end

endmodule