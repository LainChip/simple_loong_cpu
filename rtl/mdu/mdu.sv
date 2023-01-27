
`include "common.svh"
`include "decoder.svh"

module mdu (
    input clk,
    input rst_n,
    
    input stall_i,
    output div_stall_o,

    input decode_info_t decode_info_i,
    input [1:0][31:0] reg_fetch_i,
    output [31:0] mdu_res_o
);

    alu_type_t alu_type;
    opd_unsigned_t opd_unsigned;
    assign alu_type = decode_info_i.ex.alu_type;
    assign opd_unsigned = decode_info_i.ex.opd_unsigned;

    logic [31:0] mdu_opd1, mdu_opd2; // GR[rj], GR[rk]
    assign mdu_opd1 = reg_fetch_i[0];
    assign mdu_opd2 = reg_fetch_i[1];

    always_comb begin
        case (alu_type)
            `_ALU_TYPE_MUL  : begin
                
            end
            `_ALU_TYPE_MULH : begin
                
            end
            `_ALU_TYPE_DIV  : begin
                
            end
            `_ALU_TYPE_MOD  : begin
                
            end
            default : ;
        endcase
    end

    divider instance_divider (
        .clk(clk),
        .rst_n(rst_n),

        .div_valid(),
        .div_ready(),      
        .div_signed_i(~opd_unsigned),
        .Z_i(mdu_opd1),
        .D_i(mdu_opd2),

        .res_valid(),
        .res_ready(),
        .q_o(), 
        .s_o()
    );

    multiplier_v2 instance_multiplier_v2 (
        .clk(clk),
        .rst_n(rst_n),
        .stall_i(stall_i),

        .mul_signed_i(~opd_unsigned),
        .X_i(mdu_opd1),
        .Y_i(mdu_opd2),
        .res_o()
    );

endmodule
