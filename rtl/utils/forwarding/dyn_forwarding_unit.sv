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
                assign cmp_res[stage][pipe] = (data_raw_i.addr == forwarding_bus_i[pipe][stage].addr);
            end
        end
    endgenerate

    function integer hsbit(logic [$:0] vector); // [$:0] is not allowed
        integer highest_set_bit = -1;
        for (integer i = $bit(vector); i >= 0; i -= 1) begin
            if (vector[i]) begin
                highest_set_bit = i;
                break;
            end
        end
        return highest_set_bit;
    endfunction

    logic [PIPE_NUM -1 : 0] pipe_sel;
    logic [STAGE_NUM-1 : 0] stage_sel;
    always_comb begin
        for (int i = 0; i < STAGE_NUM; i += 1) begin
            stage_sel[i] = |cmp_res[i];
        end

        if (|stage_sel) begin
            pipe_sel = cmp_res[$clog2(stage_sel+1)-1];
            data_forwarding_o = forwarding_bus_i[$clog2(pipe_sel+1)-1][$clog2(stage_sel+1)-1]; // $clog2()向上取整? 视为interger所以不会溢出？性能估计很差，如果for循环数最高位1应该会好吧
        end else begin
            pipe_sel = 0;
            data_forwarding_o = data_raw_i;
        end
    end

endmodule