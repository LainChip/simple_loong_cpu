`ifdef _FPGA
    `define FULL_TEST
`endif

`ifdef _DIFFTEST_ENABLE
    `define FULL_TEST
`endif

`ifndef FULL_TEST
    `include "../bank_mpregfiles_4r2w/bank_mpregfiles_4r2w.sv"  // can be included in Makefile instead
`endif

/*--JSON--{"module_name":"reg_file","module_ver":"2","module_type":"module"}--JSON--*/
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
    input   reg_data_t [1:0] w_data_i,
    input   logic [1:0] w_en_i
);
    localparam READ_PORT  = 4;
    localparam WRITE_PORT = 2;

    bank_mpregfiles_4r2w #(
        .WIDTH(DATA_WIDTH),
        .RESET_NEED(1'b1)
    ) mp_regfile (
        .clk,
        .rst_n,
        // read port
        .ra0_i(r_addr_i[0]),
        .ra1_i(r_addr_i[1]),
        .ra2_i(r_addr_i[2]),
        .ra3_i(r_addr_i[3]),
        .rd0_o(r_data_o[0]),
        .rd1_o(r_data_o[1]),
        .rd2_o(r_data_o[2]),
        .rd3_o(r_data_o[3]),
        // write port
        .wd0_i(w_data_i[0]),
        .wd1_i(w_data_i[1]),
        .wa0_i(w_addr_i[0]),
        .wa1_i(w_addr_i[1]),
        .we0_i(w_en_i[0] & ~(w_addr_i[0] == '0)),
        .we1_i(w_en_i[1] & ~(w_addr_i[0] == '0)),
        // signal
        .conflict_o()
    );

endmodule