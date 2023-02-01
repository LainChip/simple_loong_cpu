/*
2023-1-28 v1: xrb完成
*/

`include "common.svh"
`include "decoder.svh"

module mdu (
    input clk,
    input rst_n,
    
    input [1:0] stall_i,    // stall_i : [0] for m1, [1] for m2
    input [2:0] clr_i,      // clr_i   : [0] for ex, [1] for m1, [2] for m2
    output div_busy_o,

    input decode_info_t decode_info_i,
    input [1:0][31:0] reg_fetch_i,
    output [31:0] mdu_res_o
);

    // for unit test: dump waves for gtkwave
    // `ifndef _DIFFTEST_ENABLE
    //     initial begin
    //     	$dumpfile("logs/vlt_dump.vcd");
    //     	$dumpvars();
    //     end
    // `endif

    typedef struct packed {
        alu_type_t alu_type;
        opd_unsigned_t opd_unsigned;
        logic [31:0] mdu_opd1, mdu_opd2;
    } mdu_flow_t;

    mdu_flow_t mdu_stage_0, mdu_stage_1, mdu_stage_2;

    /*======= mdu stage flow =======*/
    assign mdu_stage_0.alu_type = decode_info_i.ex.alu_type;
    assign mdu_stage_0.opd_unsigned = decode_info_i.ex.opd_unsigned;
    assign mdu_stage_0.mdu_opd1 = reg_fetch_i[0];
    assign mdu_stage_0.mdu_opd2 = reg_fetch_i[1];

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            mdu_stage_1 <= '0;
        end else if (~stall_i[0] & ~div_busy_o) begin
            if (clr_i[0]) begin
                mdu_stage_1 <= '0;                
            end else begin
                mdu_stage_1 <= mdu_stage_0;
            end 
        end
    end

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            mdu_stage_2 <= '0;
        end else if (~stall_i[1] & ~div_busy_o) begin
            if (clr_i[1]) begin
                mdu_stage_2 <= '0;                
            end else begin
                mdu_stage_2 <= mdu_stage_1;
            end 
        end
    end


    /*======= multiplier: start at stage_0 =======*/
    logic [63:0] multiply_res;
    multiplier_v2 instance_multiplier_v2 (
        .clk(clk),
        .rst_n(rst_n),
        .stall_i(stall_i | {2{div_busy_o}}),

        .mul_signed_i(~mdu_stage_0.opd_unsigned),
        .X_i(mdu_stage_0.mdu_opd1),
        .Y_i(mdu_stage_0.mdu_opd2),
        .res_o(multiply_res)
    );
    

    /*======= divider: start at stage_2 =======*/
    logic [31:0] divide_q, divide_s;
    logic div_valid_m, div_ready_s;
    logic res_valid_s, res_ready_m;

    logic is_div;
    assign is_div = (mdu_stage_2.alu_type == `_ALU_TYPE_DIV) | 
                    (mdu_stage_2.alu_type == `_ALU_TYPE_MOD);
    
    logic busy;
    always_ff @(posedge clk) begin
        if (~rst_n | clr_i[2]) begin
            busy <= 0;            
        end else begin
            case (busy)
                0: begin
                    if (div_valid_m & div_ready_s) begin
                        busy <= 1;
                    end
                end
                1: begin
                    if (res_valid_s & res_ready_m) begin
                        busy <= 0;
                    end
                end
            endcase
        end
    end
    
    assign div_valid_m = is_div & (mdu_stage_2.mdu_opd2 != 0) & ~busy;
    assign res_ready_m = busy;
    // stall signal from inside, while divider is still calculating
    assign div_busy_o = ((div_valid_m & div_ready_s) | busy) & 
                         ~(res_valid_s & res_ready_m);

    divider instance_divider (
        .clk(clk),
        .rst_n(rst_n | ~clr_i[2]),   // force reset

        .div_valid(div_valid_m),
        .div_ready(div_ready_s),      
        .div_signed_i(~mdu_stage_2.opd_unsigned),
        .Z_i(mdu_stage_2.mdu_opd1),
        .D_i(mdu_stage_2.mdu_opd2),

        .res_valid(res_valid_s),
        .res_ready(res_ready_m),
        .q_o(divide_q), 
        .s_o(divide_s)
    );


    always_comb begin
        case (mdu_stage_2.alu_type)
            `_ALU_TYPE_MUL  : begin
                mdu_res_o = multiply_res[31:0];
            end
            `_ALU_TYPE_MULH : begin
                mdu_res_o = multiply_res[63:32];
            end
            `_ALU_TYPE_DIV  : begin
                mdu_res_o = divide_q;
            end
            `_ALU_TYPE_MOD  : begin
                mdu_res_o = divide_s;
            end
            default : mdu_res_o = 0;
        endcase
    end

endmodule
