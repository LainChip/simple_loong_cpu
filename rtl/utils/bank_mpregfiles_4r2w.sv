module bank_mpregfiles_4r2w #(
    parameter int WIDTH = 32,
    parameter bit RESET_NEED = 1'b0
)(
    input clk,
    input rst_n,
    input wire[4:0] ra0_i,
    input wire[4:0] ra1_i,
    input wire[4:0] ra2_i,
    input wire[4:0] ra3_i,

    input wire[4:0] wa0_i,
    input wire[4:0] wa1_i,
    input wire we0_i,
    input wire we1_i,

    output wire[WIDTH - 1 : 0] rd0_o,
    output wire[WIDTH - 1 : 0] rd1_o,
    output wire[WIDTH - 1 : 0] rd2_o,
    output wire[WIDTH - 1 : 0] rd3_o,

    input wire[WIDTH - 1 : 0] wd0_i,
    input wire[WIDTH - 1 : 0] wd1_i,

    output wire conflict_o
);

    logic[4:0] wa_0,wa_1;
    logic[WIDTH - 1 : 0] rd0_0,rd1_0,rd2_0,rd3_0;
    logic[WIDTH - 1 : 0] rd0_1,rd1_1,rd2_1,rd3_1;
    logic[WIDTH - 1 : 0] wd_0,wd_1;
    logic we_0,we_1;

    logic[3:0] rst_cnt_q;
    if(RESET_NEED) begin
        always @(posedge clk) begin
            if(~rst_n) begin
                rst_cnt_q <= rst_cnt_q + 4'd1;
            end else begin
                rst_cnt_q <= '0;
            end
        end
    end else begin
        assign rst_cnt_q = '0;
    end

    la_mux2 #(WIDTH)output_mux0(rd0_0,rd0_1,rd0_o,ra0_i[0]);
    la_mux2 #(WIDTH)output_mux1(rd1_0,rd1_1,rd1_o,ra1_i[0]);
    la_mux2 #(WIDTH)output_mux2(rd2_0,rd2_1,rd2_o,ra2_i[0]);
    la_mux2 #(WIDTH)output_mux3(rd3_0,rd3_1,rd3_o,ra3_i[0]);

    assign conflict_o = wa1_i[0] == wa2_i[0];

    la_mux2 #(WIDTH + 6)write_mux0({wa0_i[4:0],wd0_i,we0_i},{wa1_i[4:0],wd1_i,we1_i},{wa_0,wd_0,we_0},wa0_i[0]);
    la_mux2 #(WIDTH + 6)write_mux1({wa0_i[4:0],wd0_i,we0_i},{wa1_i[4:0],wd1_i,we1_i},{wa_1,wd_1,we_1},wa1_i[0]);

    ram_3r1w_32 qram_b0_0(
        .clk,
        .addr0(ra0_i[4:0]),
        .addr1(ra1_i[4:0]),
        .addr2(ra2_i[4:0]),
        .addrw(rst_cnt_q ^ wa_0),
        .dout0(rd0_0),
        .dout1(rd1_0),
        .dout2(rd2_0),
        .din(rst_n ? wd_0 : '0),
        .wea(we_0 | ~rst_n)
    );
    ram_3r1w_32 qram_b0_1(
        .clk,
        .addr0(ra3_i[4:0]),
        .addr1('0),
        .addr2('0),
        .addrw(rst_cnt_q ^ wa_0),
        .dout0(rd3_0),
        .dout1('0),
        .dout2('0),
        .din(rst_n ? wd_0 : '0),
        .wea(we_0 | ~rst_n)
    );
    ram_3r1w_32 qram_b1_0(
        .clk,
        .addr0(ra0_i[4:0]),
        .addr1(ra1_i[4:0]),
        .addr2(ra2_i[4:0]),
        .addrw(rst_cnt_q ^ wa_1),
        .dout0(rd0_1),
        .dout1(rd1_1),
        .dout2(rd2_1),
        .din(rst_n ? wd_1 : '0),
        .wea(we_1 | ~rst_n)
    );
    ram_3r1w_32 qram_b1_1(
        .clk,
        .addr0(ra3_i[4:0]),
        .addr1('0),
        .addr2('0),
        .addrw(rst_cnt_q ^ wa_1),
        .dout0(rd3_1),
        .dout1('0),
        .dout2('0),
        .din(rst_n ? wd_1 : '0),
        .wea(we_1 | ~rst_n)
    );

endmodule