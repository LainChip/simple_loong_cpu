/*
2023-01-08 v1: xrb初步完成
*/

/*--JSON--{"module_name":"deperated","module_ver":"3","module_type":"module"}--JSON--*/
`include "common.svh"
`include "decoder.svh"

`ifdef __ALU_VER_1

module simple_alu (
    input  decode_info_t decode_info_i,
    input   [1:0][31:0] reg_fetch_i,
    input   [31:0] pc_i,
    output logic [31:0] alu_res_o
);

    alu_type_t alu_type;
    opd_type_t opd_type;
    opd_unsigned_t opd_unsigned;
    assign alu_type = decode_info_i.ex.alu_type;
    assign opd_type = decode_info_i.ex.opd_type;
    assign opd_unsigned = decode_info_i.ex.opd_unsigned;

    inst25_0_t inst25_0;
    assign inst25_0 = decode_info_i.general.inst25_0;

    logic [31:0] alu_opd1, alu_opd2; // GR[rj], GR[rk]/imm

    always_comb begin
        alu_opd1 = reg_fetch_i[0];
        case (opd_type)
            `_OPD_IMM_U5     : begin
                alu_opd2 = {27'd0, inst25_0[14:10]};
            end
            `_OPD_IMM_S12    : begin
                alu_opd2 = {{20{inst25_0[21]}}, inst25_0[21:10]};
            end   
            `_OPD_IMM_U12    : begin
                alu_opd2 = {20'd0, inst25_0[21:10]};
            end   
            `_OPD_IMM_S20    : begin
                if (alu_type == `_ALU_TYPE_ADD) begin
                    alu_opd1 = pc_i;
                end
                alu_opd2 = {inst25_0[24:5], 12'd0};
            end   
            default : begin
                alu_opd2 = reg_fetch_i[1];
            end
        endcase
    end

    // logic [63:0] product, productu;
    // logic unsigned [63:0] productu;  //效果一样
    // logic signed [63:0] product;

    always_comb begin
        // productu = alu_opd1 * alu_opd2;
        // product  = $signed(alu_opd1) * $signed(alu_opd2);
        // product  = $signed({{32{alu_opd1[31]}}, alu_opd1}) * $signed({{32{alu_opd2[31]}}, alu_opd});  // 效果一样
        case (alu_type)
            `_ALU_TYPE_ADD  : begin
                alu_res_o = alu_opd1 + alu_opd2;
            end
            `_ALU_TYPE_SUB  : begin
                alu_res_o = alu_opd1 - alu_opd2;
            end
            `_ALU_TYPE_SLT  : begin
                alu_res_o[31:1] = 31'b0;
                if (opd_unsigned) begin
                    alu_res_o[0] = alu_opd1 < alu_opd2;
                end else begin 
                    alu_res_o[0] = $signed(alu_opd1) < $signed(alu_opd2);
                end
            end
            `_ALU_TYPE_AND  : begin
                alu_res_o = alu_opd1 & alu_opd2;
            end
            `_ALU_TYPE_OR   : begin
                alu_res_o = alu_opd1 | alu_opd2;
            end
            `_ALU_TYPE_XOR  : begin
                alu_res_o = alu_opd1 ^ alu_opd2;
            end
            `_ALU_TYPE_NOR  : begin
                alu_res_o = ~(alu_opd1 | alu_opd2);
            end
            `_ALU_TYPE_SL   : begin
                alu_res_o = alu_opd1 << alu_opd2[4:0];
            end
            `_ALU_TYPE_SR   : begin
                if (opd_unsigned) begin
                    alu_res_o = alu_opd1 >> alu_opd2[4:0];
                end else begin
                    alu_res_o = $signed($signed(alu_opd1) >>> $signed(alu_opd2[4:0]));
                end
            end
            // `_ALU_TYPE_MUL  : begin
            //     alu_res_o = product[31:0];
            // end
            // `_ALU_TYPE_MULH : begin
            //     if (opd_unsigned) begin
            //         alu_res_o = productu[63:32];
            //     end else begin
            //         alu_res_o = product[63:32];
            //     end
            // end
            // `_ALU_TYPE_DIV  : begin
            //     if (alu_opd2 != 0) begin
            //         if (opd_unsigned) begin
            //             alu_res_o = alu_opd1 / alu_opd2;
            //         end else begin
            //             alu_res_o = $signed(alu_opd1) / $signed(alu_opd2);
            //         end
            //     end else begin
            //         alu_res_o = -1;
            //     end
            // end
            // `_ALU_TYPE_MOD  : begin
            //     if (alu_opd2 != 0) begin
            //         if (opd_unsigned) begin
            //             alu_res_o = alu_opd1 % alu_opd2;
            //         end else begin
            //             alu_res_o = $signed(alu_opd1) % $signed(alu_opd2);
            //         end
            //     end else begin
            //         alu_res_o = -1;
            //     end
            // end
            `_ALU_TYPE_LUI  : begin
                alu_res_o = alu_opd2;
            end
            default : begin
                alu_res_o = 0;
            end
        endcase
    end

endmodule

`endif
