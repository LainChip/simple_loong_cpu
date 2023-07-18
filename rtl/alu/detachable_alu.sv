`include "decoder.svh"

module detachable_alu #(
    parameter bit USE_LI = 0,
    parameter bit USE_INT = 1,
    parameter bit USE_SFT = 1,
    parameter bit USE_CMP = 1,
)(
    input   logic [31:0] r0_i,
    input   logic [31:0] r1_i,
    input   logic [31:0] pc_i,
    input   logic [1:0] grand_op_i,
    input   logic [1:0] op_i,
    
    output  logic [31:0] res_o
);
    // BW : definitely exist
    always_comb begin
        if (grand_op_i == `_ALU_GTYPE_BW) begin
            case (op_i)
                `_ALU_STYPE_NOR: begin
                    res_o = ~(r1_i | r0_i);
                end
                `_ALU_STYPE_AND: begin
                    res_o = r1_i & r0_i;
                end
                `_ALU_STYPE_OR: begin
                    res_o = r1_i | r0_i;
                end
                `_ALU_STYPE_XOR: begin
                    res_o = r1_i ^ r0_i;
                end
            endcase
        end 
    end

    
    if (USE_INT) begin
    // INT
    always_comb begin
        if (grand_op_i == `_ALU_GTYPE_INT) begin
            case (op_i)
                `_ALU_STYPE_ADD: begin // 2'b00
                    res_o = r1_i + r0_i;
                end
                `_ALU_STYPE_SUB: begin // 2'b10
                    res_o = r1_i - r0_i;
                end
                default: begin
                    res_o = 0;
                end
            endcase
        end
    end
    end else if (USE_LI) begin
    // LI
    always_comb begin
        if (grand_op_i == `_ALU_GTYPE_LI) begin
            case (op_i)
                `_ALU_STYPE_LUI: begin  // 2'b01
                    res_o = {r0_i[19:0], 12'd0};
                end
                `_ALU_STYPE_PCPLUS4: begin  // 2'b10
                    res_o = r1_i + r0_i;
                end
                `_ALU_STYPE_PCADDUI: begin  // 2'b11
                    res_o = r0_i + pc_i;
                end
                default: begin // 2'b00
                    res_o = 0; // `_ALU_STYPE_LIEMPTYSLOT ...
                end
            endcase
        end
    end
    end

    if (USE_SFT) begin
    // SFT
    always_comb begin
        if (grand_op_i == `_ALU_GTYPE_SFT) begin
            case (op_i)
                `_ALU_STYPE_SLL: begin
                    res_o = r1_i << r0_i[4:0];
                end
                `_ALU_STYPE_SRL: begin
                    res_o = r1_i >> r0_i[4:0];
                end
                `_ALU_STYPE_SRA: begin
                    res_o = $signed($signed(r1_i) >>> $signed(r0_i[4:0]));
                end
                default: begin
                    res_o = 0;
                end
            endcase
        end
    end
    end

    if (USE_CMP) begin
    // CMP
    always_comb begin
        if (grand_op_i == `_ALU_GTYPE_CMP) begin
            case (op_i)
                `_ALU_STYPE_SLT: begin
                    res_o[31:1] = 31'b0;
                    res_o[0] = r1_i < r0_i;
                end
                `_ALU_STYPE_SLTU: begin
                    res_o[31:1] = 31'b0;
                    res_o[0] = $signed(r1_i) < $signed(r0_i);
                end
                default: begin
                    res_o = 0;
                end
            endcase
        end
    end
    end
    

endmodule
