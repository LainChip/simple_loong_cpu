`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/05/20 21:09:20
// Design Name: 
// Module Name: sram
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module spram #(
    parameter ADDR_WIDTH =  6,
    parameter DATA_WIDTH = 32,
    parameter WRITE_MODE = "write_first"
)(
    input   clk,
    input   reset,

    input   en,
    input   we,
    input   [ADDR_WIDTH - 1:0] addr,
    input   [DATA_WIDTH - 1:0] wdata,
    output  [DATA_WIDTH - 1:0] rdata
    );
    // xpm_memory_spram: Single Port RAM
    // Xilinx Parameterized Macro, version 2019.2


    xpm_memory_spram #(
        .ADDR_WIDTH_A(ADDR_WIDTH),              // DECIMAL
        .AUTO_SLEEP_TIME(0),                    // DECIMAL
        .BYTE_WRITE_WIDTH_A(DATA_WIDTH),        // DECIMAL
        .CASCADE_HEIGHT(0),                     // DECIMAL
        .ECC_MODE("no_ecc"),                    // String
        .MEMORY_INIT_FILE("none"),              // String
        .MEMORY_INIT_PARAM("0"),                // String
        .MEMORY_OPTIMIZATION("true"),           // String
        .MEMORY_PRIMITIVE("block"),             // String
        .MEMORY_SIZE(DATA_WIDTH << ADDR_WIDTH), // DECIMAL
        .MESSAGE_CONTROL(0),                    // DECIMAL
        .READ_DATA_WIDTH_A(DATA_WIDTH),         // DECIMAL
        .READ_LATENCY_A(1),                     // DECIMAL
        .READ_RESET_VALUE_A("0"),               // String
        .RST_MODE_A("SYNC"),                    // String
        .SIM_ASSERT_CHK(0),                     // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
        .USE_MEM_INIT(1),                       // DECIMAL
        .WAKEUP_TIME("disable_sleep"),          // String
        .WRITE_DATA_WIDTH_A(DATA_WIDTH),        // DECIMAL
        .WRITE_MODE_A(WRITE_MODE)               // String
    )
    xpm_memory_spram_inst (
        .dbiterra(       ),             // 1-bit output: Status signal to indicate double bit error occurrence
                                        // on the data output of port A.

        .douta(rdata),                  // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
        .sbiterra(       ),             // 1-bit output: Status signal to indicate single bit error occurrence
                                        // on the data output of port A.

        .addra(addr),                   // ADDR_WIDTH_A-bit input: Address for port A write and read operations.
        .clka(clk),                     // 1-bit input: Clock signal for port A.
        .dina(wdata),                   // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
        .ena(en),                       // 1-bit input: Memory enable signal for port A. Must be high on clock
                                        // cycles when read or write operations are initiated. Pipelined
                                        // internally.

        .injectdbiterra(1'b0),          // 1-bit input: Controls double bit error injection on input data when
                                        // ECC enabled (Error injection capability is not available in
                                        // "decode_only" mode).

        .injectsbiterra(1'b0),          // 1-bit input: Controls single bit error injection on input data when
                                        // ECC enabled (Error injection capability is not available in
                                        // "decode_only" mode).

        .regcea(1'b1),                  // 1-bit input: Clock Enable for the last register stage on the output
                                        // data path.

        .rsta(reset),                   // 1-bit input: Reset signal for the final port A output register stage.
                                        // Synchronously resets output port douta to the value specified by
                                        // parameter READ_RESET_VALUE_A.

        .sleep(1'b0),                   // 1-bit input: sleep signal to enable the dynamic power saving feature.
        .wea(we)                        // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
                                        // for port A input data port dina. 1 bit wide when word-wide writes are
                                        // used. In byte-wide write configurations, each bit controls the
                                        // writing one byte of dina to address addra. For example, to
                                        // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
                                        // is 32, wea would be 4'b0010.

    );

    // End of xpm_memory_spram_inst instantiation          

endmodule