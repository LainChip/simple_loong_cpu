`include "common.svh"
`include "forwarding_type.svh"

module dyn_forwarding_unit #(
    parameter int DATA_WIDTH = 32,
    parameter int STAGE_NUM = 3,
    parameter int PIPE_NUM = 2
) (
    input  forwarding_data_t [PIPE_NUM-1:0][STAGE_NUM-1:0] forwarding_bus_i,
    input  forwarding_data_t data_raw_i,
    
    output forwarding_data_t data_forwarding_o
);
    // for gtkwave
    initial begin
    	$dumpfile("logs/vlt_dump.vcd");
    	$dumpvars();
    end

    localparam int SRC_NUM = PIPE_NUM * STAGE_NUM;
    // forward_bus_i: [][2] from m2, [][1] from m1, [][0] from wb 

    forwarding_data_t [SRC_NUM-1:0] forwarding_src;
    logic [SRC_NUM-1 : 0] cmp_res;
    // e.g. m1_p1 | m1_p0 | m2_p1 | m2_p0 | wb_p1 | wb_p0       
    generate
        for (genvar stage = 0; stage < STAGE_NUM; stage += 1) begin
            for (genvar pipe = 0; pipe < PIPE_NUM; pipe += 1) begin
                assign forwarding_src[stage*2+pipe] = forwarding_bus_i[pipe][stage];
            end
        end
        for (genvar i = 0; i < SRC_NUM; i++) begin
            cmp_res[i] = (data_raw_i.addr == forwarding_src[i].addr);
        end
    endgenerate

    always_comb begin
        if (|cmp_res) begin
            data_forwarding_o = data_raw_i;
        end else begin
            for (int i = SRC_NUM-1; i >= 0; i--) begin
                if (cmp_res[i]) begin
                    data_forwarding_o = forwarding_src[i];
                end
            end
        end
    end

endmodule