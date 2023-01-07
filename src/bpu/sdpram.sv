module sdpram #(
    parameter ADDR_WIDTH =  6,
    parameter DATA_WIDTH = 32,
    parameter WRITE_MODE = "write_first" // can be read or write first
) (
    input   clk,
    input   reset,

    input   en,
    input   we,
    input   [ADDR_WIDTH - 1:0] raddr,
    input   [ADDR_WIDTH - 1:0] waddr,
    input   [DATA_WIDTH - 1:0] wdata,
    output  [DATA_WIDTH - 1:0] rdata
);

    wire [DATA_WIDTH - 1:0] dout;
    reg  [DATA_WIDTH - 1:0] din;
    reg conflict;
    always @(posedge clk ) begin
        if (reset) begin
            conflict <= 1'b0;
            din <= 0;
        end else begin
            conflict <= (raddr == waddr) & we;
            din <= wdata;
        end
        
    end

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(ADDR_WIDTH),      // DECIMAL
        .ADDR_WIDTH_B(ADDR_WIDTH),      // DECIMAL
        .AUTO_SLEEP_TIME(0),            // DECIMAL
        .BYTE_WRITE_WIDTH_A(DATA_WIDTH),// DECIMAL
        .CASCADE_HEIGHT(0),             // DECIMAL
        .CLOCKING_MODE("common_clock"), // String
        .ECC_MODE("no_ecc"),            // String
        .MEMORY_INIT_FILE("none"),      // String
        .MEMORY_INIT_PARAM("0"),        // String
        .MEMORY_OPTIMIZATION("true"),   // String
        .MEMORY_PRIMITIVE("block"),     // String
        .MEMORY_SIZE(DATA_WIDTH << ADDR_WIDTH), // DECIMAL
        .MESSAGE_CONTROL(0),            // DECIMAL
        .READ_DATA_WIDTH_B(DATA_WIDTH), // DECIMAL
        .READ_LATENCY_B(1),             // DECIMAL
        .READ_RESET_VALUE_B("0"),       // String
        .RST_MODE_A("SYNC"),            // String
        .RST_MODE_B("SYNC"),            // String
        .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
        .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
        .USE_MEM_INIT(1),               // DECIMAL
        .WAKEUP_TIME("disable_sleep"),  // String
        .WRITE_DATA_WIDTH_A(DATA_WIDTH),// DECIMAL
        .WRITE_MODE_B("read_first")     // String
    )
    xpm_memory_sdpram_inst (
        .dbiterrb(),                    // 1-bit output: Status signal to indicate double bit error occurrence
                                        // on the data output of port B.

        .doutb(dout),                   // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
        .sbiterrb(),                    // 1-bit output: Status signal to indicate single bit error occurrence
                                        // on the data output of port B.

        .addra(waddr),                  // ADDR_WIDTH_A-bit input: Address for port A write operations.
        .addrb(raddr),                  // ADDR_WIDTH_B-bit input: Address for port B read operations.
        .clka(clk),                     // 1-bit input: Clock signal for port A. Also clocks port B when
                                        // parameter CLOCKING_MODE is "common_clock".

        .clkb(clk),                     // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
                                        // "independent_clock". Unused when parameter CLOCKING_MODE is
                                        // "common_clock".

        .dina(wdata),                   // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
        .ena(en),                       // 1-bit input: Memory enable signal for port A. Must be high on clock
                                        // cycles when write operations are initiated. Pipelined internally.

        .enb(en),                       // 1-bit input: Memory enable signal for port B. Must be high on clock
                                        // cycles when read operations are initiated. Pipelined internally.

        .injectdbiterra(1'b0),          // 1-bit input: Controls double bit error injection on input data when
                                        // ECC enabled (Error injection capability is not available in
                                        // "decode_only" mode).

        .injectsbiterra(1'b0),          // 1-bit input: Controls single bit error injection on input data when
                                        // ECC enabled (Error injection capability is not available in
                                        // "decode_only" mode).

        .regceb(1'b1),                  // 1-bit input: Clock Enable for the last register stage on the output
                                        // data path.

        .rstb(reset),                   // 1-bit input: Reset signal for the final port B output register stage.
                                        // Synchronously resets output port doutb to the value specified by
                                        // parameter READ_RESET_VALUE_B.

        .sleep(1'b0),                   // 1-bit input: sleep signal to enable the dynamic power saving feature.
        .wea(we)                        // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
                                        // for port A input data port dina. 1 bit wide when word-wide writes are
                                        // used. In byte-wide write configurations, each bit controls the
                                        // writing one byte of dina to address addra. For example, to
                                        // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
                                        // is 32, wea would be 4'b0010.

    );

    generate
        if (WRITE_MODE == "write_first") begin
            assign rdata = conflict ? din : dout;
        end else begin
            assign rdata = dout;
        end
    endgenerate
    
endmodule
