`include "../common.svh"
`include "forwarding_type.svh"

module dyn_forwarding_unit #(
    parameter int SRC_NUM = 6
) (
    input  forwarding_data_t [SRC_NUM-1:0] forwarding_bus_i,
    input  forwarding_data_t data_raw_i,
    
    output forwarding_data_t data_forwarding_o
);
    /* assume forward_bus_i: high bit with high priority */

    forwarding_data_t [SRC_NUM-1 : 0] forwarding_src;
    logic [SRC_NUM-1 : 0] cmp_res;     
    assign forwarding_src = forwarding_bus_i; // for potential extention
    generate
        for (genvar i = 0; i < SRC_NUM; i++) begin
            assign cmp_res[i] = (data_raw_i.addr == forwarding_src[i].addr);
        end
    endgenerate

    logic [$clog2(SRC_NUM)-1 : 0] leading_zero;
    logic sel_raw;
    lzc #(
        .WIDTH(SRC_NUM),
        .MODE (1'b1)
    ) count_leading_zero(
        .in_i(cmp_res),
        .cnt_o(leading_zero),
        .empty_o(sel_raw)
    );

    always_comb begin
        if (sel_raw) begin
            data_forwarding_o = data_raw_i;
        end else begin
            data_forwarding_o = forwarding_src[SRC_NUM-1-leading_zero]; 
            // can '-' be improved ?
        end
    end

endmodule