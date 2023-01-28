`include "common.svh"
`include "decoder.svh"
`include "tlb.svh"

`ifdef _TLB_VER_1

module tlb #(
    parameter int TLB_ENTRY_NUM = `_TLB_ENTRY_NUM,
    parameter int TLB_PORT = `_TLB_PORT
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
    input   [$clog2(TLB_ENTRY_NUM)-1:0]        r_index_i   ,
    output  tlb_r_resp_t                        r_resp_o    ,
    //invalid
    input   tlb_inv_req_t                       inv_req_i   

);

tlb_entry_t [TLB_ENTRY_NUM-1 : 0] tlb_entry [TLB_ENTRY_NUM-1 : 0];

//search
generate
    for(genvar i = 0; i < TLB_PORT; ++i) begin
        tlb_lookup tlb_lookup_item(
            .tlb_entry_i(tlb_entry),
            .req_i(s_req_i[i]),
            .resp_o(s_resp_o[i])
        )
    end
endgenerate


//write
always_ff @(posedge clk) begin
    if(w_req_i.we) begin
        tlb_entry.vppn [w_req_i.index] <= w_req_i.vppn;
        tlb_entry.asid [w_req_i.index] <= w_req_i.asid;
        tlb_entry.g    [w_req_i.index] <= w_req_i.g; 
        tlb_entry.ps   [w_req_i.index] <= w_req_i.ps;  
        tlb_entry.ppn0 [w_req_i.index] <= w_req_i.ppn0;
        tlb_entry.plv0 [w_req_i.index] <= w_req_i.plv0;
        tlb_entry.mat0 [w_req_i.index] <= w_req_i.mat0;
        tlb_entry.d0   [w_req_i.index] <= w_req_i.d0;
        tlb_entry.v0   [w_req_i.index] <= w_req_i.v0; 
        tlb_entry.ppn1 [w_req_i.index] <= w_req_i.ppn1;
        tlb_entry.plv1 [w_req_i.index] <= w_req_i.plv1;
        tlb_entry.mat1 [w_req_i.index] <= w_req_i.mat1;
        tlb_entry.d1   [w_req_i.index] <= w_req_i.d1;
        tlb_entry.v1   [w_req_i.index] <= w_req_i.v1;   
    end 
end

//read
assign r_resp_o.vppn  =  tlb_entry[r_index_i].vppn ; 
assign r_resp_o.asid  =  tlb_entry[r_index_i].asid ; 
assign r_resp_o.g     =  tlb_entry[r_index_i].g    ; 
assign r_resp_o.ps    =  tlb_entry[r_index_i].ps   ; 
assign r_resp_o.e     =  tlb_entry[r_index_i].e    ; 
assign r_resp_o.v0    =  tlb_entry[r_index_i].v0   ; 
assign r_resp_o.d0    =  tlb_entry[r_index_i].d0   ; 
assign r_resp_o.mat0  =  tlb_entry[r_index_i].mat0 ; 
assign r_resp_o.plv0  =  tlb_entry[r_index_i].plv0 ; 
assign r_resp_o.ppn0  =  tlb_entry[r_index_i].ppn0 ; 
assign r_resp_o.v1    =  tlb_entry[r_index_i].v1   ; 
assign r_resp_o.d1    =  tlb_entry[r_index_i].d1   ; 
assign r_resp_o.mat1  =  tlb_entry[r_index_i].mat1 ; 
assign r_resp_o.plv1  =  tlb_entry[r_index_i].plv1 ; 
assign r_resp_o.ppn1  =  tlb_entry[r_index_i].ppn1 ; 

//invalid
generate
    for (genvar i = 0; i <  TLB_ENTRY_NUM; i = i + 1 ) begin
        always_ff @(posedge clk) begin
            if(w_req_i.we && (w_req_i.index == i))begin
                tlb_entry[i].e <= w_req_i.e;
            end
            else if (inv_req_i.en) begin
                if (inv_req_i.op == 5'd0 || inv_req_i.op == 5'd1) begin
                    tlb_entry[i].e < = 1'b0;
                end else if(inv_req_i.op == 5'd2)begin
                    if(tlb_entry[i].g)begin
                        tlb_entry[i].e < = 1'b0;
                    end
                end else if(inv_req_i.op == 5'd3)begin
                    if(!tlb_entry[i].g)begin
                        tlb_entry[i].e < = 1'b0;
                    end
                end else if(inv_req_i.op == 5'd4)begin
                    if(!tlb_entry[i].g 
                    && (tlb_entry[i].asid == inv_req_i.asid))begin
                        tlb_entry[i].e < = 1'b0;
                    end
                end else if(inv_req_i.op == 5'd5)begin
                    if( !tlb_entry[i].g 
                    &&  (tlb_entry[i].asid == inv_req_i.asid)
                    &&  ((tlb_entry[i].ps == 6'd12) ? 
                        (tlb_entry[i].vppn == inv_req_i.vpn) :
                        (tlb_entry[i].vppn[18:10] == inv_req_i.vpn[18:10]))
                    ) begin
                        tlb_entry[i].e < = 1'b0;
                    end
                end else if(inv_req_i.op == 5'd6)begin
                if( tlb_entry[i].g 
                    ||  (tlb_entry[i].asid == inv_req_i.asid)
                    &&  ((tlb_entry[i].ps == 6'd12) ? 
                        (tlb_entry[i].vppn == inv_req_i.vpn) :
                        (tlb_entry[i].vppn[18:10] == inv_req_i.vpn[18:10]))
                    ) begin
                        tlb_entry[i].e < = 1'b0;
                    end
                end
            end
        end
    end
endgenerate


endmodule : tlb

`endif 