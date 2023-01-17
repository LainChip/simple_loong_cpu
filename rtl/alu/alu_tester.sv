`include "common.svh"
`include "decoder.svh"
`include "alu.sv"

module alu_tester (
    input alu_type_t alu_type,
    input opd_type_t opd_type,
    input opd_unsigned,
    input [4 :0] ui5,
    input [11:0] si12,
    input [19:0] si20,

    input [31:0] reg_fetch0,
    input [31:0] reg_fetch1,

    input [31:0] pc,
    
    output [31:0] alu_res
);
    // // for gtkwave
    // initial begin
    // 	$dumpfile("logs/vlt_dump.vcd");
    // 	$dumpvars();
    // end

    decode_info_t decode_info = 0;
    inst25_0_t inst25_0;
    logic [1:0][31:0] reg_fetch;

    assign reg_fetch[0] = reg_fetch0;
    assign reg_fetch[1] = reg_fetch1;

    always_comb begin
        inst25_0 = 0;
        case (opd_type)
            `_OPD_IMM_U5  : inst25_0[14:10] = ui5;
            `_OPD_IMM_S12, 
            `_OPD_IMM_U12 : inst25_0[21:10] = si12;
            `_OPD_IMM_S20 : inst25_0[24:5] = si20;
            default : ;
        endcase
    end

    always_comb begin
        decode_info.ex.alu_type = alu_type;
        decode_info.ex.opd_type = opd_type;
        decode_info.ex.opd_unsigned = opd_unsigned;
        decode_info.general.inst25_0 = inst25_0;
    end

    alu alu (
        .decode_info_i(decode_info),
        .reg_fetch_i(reg_fetch),
        .pc_i(pc),
        .alu_res_o(alu_res)
    );

endmodule : alu_tester
