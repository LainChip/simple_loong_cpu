`ifndef _FPGA
    `include "../bank_mpregfiles_4r2w/bank_mpregfiles_4r2w.sv"
`endif

module reg_file #(
    parameter int DATA_WIDTH = 32,
    // fixed READ_PORT = 4, WRITE_PORT = 2 (odd/even)
    // fixed DEPTH = 32
    parameter type reg_data_t = logic [DATA_WIDTH-1:0],
    parameter type reg_addr_t = logic [4 : 0] 
)(
    input clk,
    input rst_n,
    // read port
    input   reg_addr_t [3:0] r_addr_i,
    output  reg_data_t [3:0] r_data_o,
    // write port
    input   reg_addr_t [1:0] w_addr_i,
    output  reg_data_t [1:0] w_data_i
);
    localparam READ_PORT  = 4;
    localparam WRITE_PORT = 2;

    reg_data_t [3:0] read_data;

    generate
        for (genvar i = 0; i < READ_PORT; i++) begin
            la_mux2 #(DATA_WIDTH)read_out_i('0, read_data[i], r_data_o[i], (r_addr_i[i] == '0));
        end
    endgenerate

    bank_mpregfiles_4r2w #(
        .WIDTH(32),
        .RESET_NEED(1'b1)
    ) mp_regfile (
        .clk,
        .rst_n,
        // read port
        .ra0_i(r_addr_i[0]),
        .ra1_i(r_addr_i[1]),
        .ra2_i(r_addr_i[2]),
        .ra3_i(r_addr_i[3]),
        .rd0_o(read_data[0]),
        .rd1_o(read_data[1]),
        .rd2_o(read_data[2]),
        .rd3_o(read_data[3]),
        // write port
        .wd0_i(w_data_i[0]),
        .wd1_i(w_data_i[1]),
        .wa0_i(w_addr_i[0]),
        .wa1_i(w_addr_i[1]),
        .we0_i(~(w_addr_i[0] == '0)),
        .we1_i(~(w_addr_i[0] == '0)),
        // signal
        .conflict_o()
    );

endmodule