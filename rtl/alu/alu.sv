/*
v1
*/

`include "common.svh"
`include "decoder.svh"

`ifdef _ALU_VER_1

module alu(
    input  decode_info_t decode_info_i,
    input   [31:0] pc_i,
    output  [31:0] alu_res_o
);

alu_type_t alu_type = decode_info_i.ex.alu_type;
opd_type_t opd_type = decode_info_i.ex.opd_type;
opd_unsigned_t opd_unsigned = decode_info_i.ex.opd_unsigned;

logic [31:0] alu_opd1;
logic [31:0] alu_opd2;

always_comb begin
    case (alu_type)
        `_ALU_TYPE_NIL  : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_ADD  : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_SUB  : begin
            alu_res_o = alu_opd1 - alu_opd2;
        end
        `_ALU_TYPE_SLT  : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_AND  : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_OR   : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_XOR  : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_NOR  : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_SL   : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_SR   : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_MUL  : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_MULH : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_DIV  : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_MOD  : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
        `_ALU_TYPE_LUI  : begin
            alu_res_o = alu_opd1 + alu_opd2;
        end
    endcase
end

endmodule

`endif