`include "../../common.svh"
`include "forwarding_type.svh"

module dyn_forwarding_unit #(
    parameter int DATA_WIDTH = 32,
    parameter int STAGE_NUM = 3,
    parameter int PIPE_NUM = 2
) (
    input  forwarding_data_t [PIPE_NUM-1:0][STAGE_NUM-1:0] forward_bus_i,
    input  forwarding_data_t data_raw_i,
    
    output forwarding_data_t data_forwarding_o
);
    localparam int SRC_NUM = PIPE_NUM * STAGE_NUM;
    // forward_bus_i: [][2] from m2, [][1] from m1, [][0] from wb 

    /* get cmp signal of reg addr */
    logic [STAGE_NUM-1:0][PIPE_NUM-1:0] cmp_res;
    /* assume STAGE_NUM = 3 and PIPE_NUM = 2
     * data_src: [1](pipe1) | [0](pipe0) 
     *   [2](m1)                         
     *   [1](m2)   ...is addr equal...  
     *   [0](wb)              
    */          
    generate
        for (genvar stage = 0; stage < STAGE_NUM; stage += 1) begin
            for (genvar pipe = 0; pipe < PIPE_NUM; pipe += 1) begin
                assign cmp_res[stage][pipe] = (data_raw_i.addr == forward_bus_i[pipe][stage].addr);
            end
        end
    endgenerate

    // function floor

    // endfunction

    logic [PIPE_NUM -1 : 0] pipe_sel;
    logic [STAGE_NUM-1 : 0] stage_sel;
    always_comb begin
        for (int i = 0; i < STAGE_NUM; i += 1) begin
            stage_sel[i] = |cmp_res[i];
        end

        if (|stage_sel) begin
            pipe_sel = cmp_res[$clog2(stage_sel+1)-1];
            data_forwarding_o = forward_bus_i[$clog2(pipe_sel+1)-1][$clog2(stage_sel+1)-1]; // $clog2()向上取整? 好像溢出也能正确计算，不过还是要自己写个function吧
        end else begin
            pipe_sel = 0;
            data_forwarding_o = data_raw_i;
        end
    end

endmodule