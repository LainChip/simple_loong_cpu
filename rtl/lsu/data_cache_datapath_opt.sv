`include "common.svh"

/* 
This module describe a data path inside banked cache.
By default, it got 2 bank, 8 word / index, 16 word / lane
This module is a None-stall module.
All stall should be handled in controll logic.
*/

// This module  same to be no problem !
// Move on cache controller...

// 2022.8.3: I thinking this module is a little bit too complex and unbalenced in logic.
// I will cut bram-latency to one cycle, to avoid that complex.
module data_cache_datapath_opt #(
    parameter int page_shift_len = 12,
    parameter int word_shift_len = 2,
    parameter int bank_shift_len = 1,
    parameter int index_len = 8,
    parameter int set_ass = 2
) (
    input clk,  // Clock
    input rst_n,  // Asynchronous reset active low
    output conflict,  // When conflict happend, only second request is answerd

    input logic [1:0] valid,
    input logic [1:0][page_shift_len - word_shift_len - 1 : 0] req_r_addr,

    input logic [3:0] req_w_enable,
    input logic [$clog2(set_ass) - 1 : 0] req_w_set_sel,
    input logic [page_shift_len - word_shift_len - 1 : 0] req_w_addr,
    input logic [(1 << word_shift_len) * 8 - 1 : 0] req_w_data,

    output logic [1:0][set_ass - 1 : 0][(1 << word_shift_len) - 1 : 0][7 : 0] resp_r_data
);

  localparam int inbank_shift_len = page_shift_len - word_shift_len - bank_shift_len - index_len;
  localparam int word_size = 1 << word_shift_len;
  localparam int bank_inout_size = word_size * set_ass;
  localparam int bank_elem_num = 1 << (index_len + inbank_shift_len);
  localparam int bank_num = 1 << bank_shift_len;

  /*
		All read has 2 cycles delay.
		After request answered, result will be ready in 2 cycle.
	*/

  // Instance Banks and leave hook
  logic [bank_num - 1 : 0][inbank_shift_len + index_len - 1 : 0] bank_r_addr;
  logic [bank_num - 1 : 0][word_size * set_ass * 8 - 1 : 0] bank_r_data;
  logic [inbank_shift_len + index_len - 1 : 0] bank_w_addr;  // Additional set_sel signal needed
  logic [word_size * 8 - 1 : 0] bank_w_data;
  logic [bank_num - 1 : 0][3:0] bank_w_enable;

  // Bank generation (by usage of Macro)
  generate
    for (genvar bank_id = 0; bank_id < bank_num; bank_id += 1) begin
      logic [set_ass - 1 : 0][word_size * 8 - 1 : 0] bank_r_init;
      assign bank_r_data[bank_id] = bank_r_init;
      for (genvar way_id = 0; way_id < set_ass; way_id += 1) begin
        logic [3:0] we;
        assign we = bank_w_enable[bank_id] & {4{(way_id == req_w_set_sel)}};
        simpleDualPortRamByteen #(
            .dataWidth(8 << word_shift_len),
            .ramSize(1 << (index_len + inbank_shift_len)),
            .latency(1),  // Cut down the latency.
            .readMuler(1)
        ) bram_core (
            .clk     (clk),
            .rst_n   (rst_n),
            .addressA(bank_w_addr),
            .we      (we),
            .addressB(bank_r_addr[bank_id]),
            .inData  (bank_w_data),
            .outData (bank_r_init[way_id])
        );
      end
    end
  endgenerate

  // This part, we will generate mux controll signal, and generate conflict signal.
  // Mux controll declearation
  logic [page_shift_len - word_shift_len - 1 : 0] delay_1_req_w_addr;
  logic [set_ass - 1 : 0] delay_1_req_w_sel;
  logic [3:0] delay_1_req_w_enable;
  logic [(1 << word_shift_len) - 1 : 0][7 : 0] delay_1_req_w_data;
  //   logic [page_shift_len - word_shift_len - 1 : 0] delay_2_req_w_addr;
  //   logic [set_ass - 1 : 0] delay_2_req_w_sel;
  //   logic [3:0] delay_2_req_w_enable;
  //   logic [(1 << word_shift_len) - 1 : 0][7 : 0] delay_2_req_w_data;
  //   logic [page_shift_len - word_shift_len - 1 : 0] delay_3_req_w_addr;
  //   logic [set_ass - 1 : 0] delay_3_req_w_sel;
  //   logic [3:0] delay_3_req_w_enable;
  //   logic [(1 << word_shift_len) - 1 : 0][7 : 0] delay_3_req_w_data;
  //   logic [page_shift_len - word_shift_len - 1 : 0] delay_4_req_w_addr;
  //   logic [set_ass - 1 : 0] delay_4_req_w_sel;
  //   logic [3:0] delay_4_req_w_enable;
  //   logic [(1 << word_shift_len) - 1 : 0][7 : 0] delay_4_req_w_data;


  logic [1:0][page_shift_len - word_shift_len - 1 : 0] delay_1_req_r_addr;
  logic [1:0][page_shift_len - word_shift_len - 1 : 0] delay_2_req_r_addr;
  logic [1:0][bank_shift_len - 1 : 0] addr_r_bank_bits;
  assign addr_r_bank_bits[0] = req_r_addr[0][bank_shift_len-1:0];
  assign addr_r_bank_bits[1] = req_r_addr[1][bank_shift_len-1:0];
  logic [1:0][bank_shift_len - 1 : 0] delay_1_addr_r_bank_bits;
  assign delay_1_addr_r_bank_bits[0] = delay_1_req_r_addr[0][bank_shift_len-1:0];
  assign delay_1_addr_r_bank_bits[1] = delay_1_req_r_addr[1][bank_shift_len-1:0];
  //   logic [1:0][bank_shift_len - 1 : 0] delay_2_addr_r_bank_bits;
  //   assign delay_2_addr_r_bank_bits[0] = delay_2_req_r_addr[0][bank_shift_len-1:0];
  //   assign delay_2_addr_r_bank_bits[1] = delay_2_req_r_addr[1][bank_shift_len-1:0];
  always_ff @(posedge clk) begin
    begin
      delay_1_req_r_addr <= req_r_addr;
      // //   delay_2_req_r_addr <= delay_1_req_r_addr;
      delay_1_req_w_addr <= req_w_addr;
      delay_1_req_w_sel <= req_w_set_sel;
      delay_1_req_w_enable <= req_w_enable;
      delay_1_req_w_data <= req_w_data;
      //   delay_2_req_w_addr <= delay_1_req_w_addr;
      //   delay_2_req_w_sel <= delay_1_req_w_sel;
      //   delay_2_req_w_enable <= delay_1_req_w_enable;
      //   delay_2_req_w_data <= delay_1_req_w_data;
      //   delay_3_req_w_addr <= delay_2_req_w_addr;
      //   delay_3_req_w_sel <= delay_2_req_w_sel;
      //   delay_3_req_w_enable <= delay_2_req_w_enable;
      //   delay_3_req_w_data <= delay_2_req_w_data;
      //   delay_4_req_w_addr <= delay_3_req_w_addr;
      //   delay_4_req_w_sel <= delay_3_req_w_sel;
      //   delay_4_req_w_enable <= delay_3_req_w_enable;
      //   delay_4_req_w_data <= delay_3_req_w_data;
    end
  end

  logic [bank_num - 1 : 0] bank_mux;
  generate
    for (genvar bank_id = 0; bank_id < bank_num; bank_id += 1) begin
      assign bank_mux[bank_id] = (addr_r_bank_bits[0] == bank_id && valid[0]) ? 1'b0 : 1'b1;
    end
  endgenerate

  // Generate conflict
  assign conflict = (&valid) & (addr_r_bank_bits[0] == addr_r_bank_bits[1]) &
	 (req_r_addr[0][page_shift_len - word_shift_len - 1 : bank_shift_len] != req_r_addr[1][page_shift_len - word_shift_len - 1 : bank_shift_len]);

  // This part, we will use bank_mux signal to generate 
  // For read signal
  logic [1:0][set_ass - 1 : 0][(1 << word_shift_len) - 1 : 0][7 : 0] stage_1_resp_r_data;
  generate
    for (genvar bank_id = 0; bank_id < bank_num; bank_id += 1) begin
      assign bank_r_addr[bank_id] = bank_mux[bank_id] ? req_r_addr[1][inbank_shift_len + index_len : bank_shift_len]:req_r_addr[0][inbank_shift_len + index_len : bank_shift_len];
    end
    for (genvar req_id = 0; req_id < 2; req_id += 1) begin
      //   always_comb begin
      //     resp_r_data[req_id] = bank_r_data[delay_2_addr_r_bank_bits[req_id]];
      //     for (int byte_id = 0; byte_id < 4; byte_id += 1) begin
      //       if((delay_2_req_w_addr == delay_2_req_r_addr[req_id]) && (delay_2_req_w_enable[byte_id]))
      // 				begin
      //         resp_r_data[req_id][delay_2_req_w_sel][byte_id] = delay_2_req_w_data[byte_id]; // Forwarding logic.
      //       end
      //       if((delay_1_req_w_addr == delay_2_req_r_addr[req_id]) && (delay_1_req_w_enable[byte_id]))
      // 				begin
      //         resp_r_data[req_id][delay_1_req_w_sel][byte_id] = delay_1_req_w_data[byte_id]; // Forwarding logic.
      //       end
      //     end
      //   end
      logic forward_enable_1;
      logic forward_enable_2;
      logic [(1 << word_shift_len) - 1:0][7:0] forward_w_data_1;
      logic [(1 << word_shift_len) - 1:0][7:0] forward_w_data_2;
      assign forward_w_data_1 = req_w_data;
      assign forward_w_data_2 = delay_1_req_w_data;
      assign forward_enable_1 = req_w_addr == delay_1_req_r_addr[req_id];
      assign forward_enable_2 = delay_1_req_w_addr == delay_1_req_r_addr[req_id];
      always_comb begin
        stage_1_resp_r_data[req_id] = bank_r_data[delay_1_addr_r_bank_bits[req_id]];
        for (int byte_id = 0; byte_id < 4; byte_id += 1) begin
          if (forward_enable_2 && delay_1_req_w_enable[byte_id]) begin
            stage_1_resp_r_data[req_id][delay_1_req_w_sel][byte_id] = forward_w_data_2[byte_id];
          end
          if (forward_enable_1 && req_w_enable[byte_id]) begin
            stage_1_resp_r_data[req_id][req_w_set_sel][byte_id] = forward_w_data_1[byte_id];
          end
        end
      end
      always_ff @(posedge clk) begin
        resp_r_data[req_id] <= stage_1_resp_r_data[req_id];
      end
    end
  endgenerate

  // For write signals
  assign bank_w_data = req_w_data;
  assign bank_w_addr = req_w_addr[inbank_shift_len+index_len : bank_shift_len];
  generate
    for (genvar bank_id = 0; bank_id < bank_num; bank_id += 1) begin
      assign bank_w_enable[bank_id] = (req_w_addr[bank_shift_len - 1:0] == bank_id) ? req_w_enable : '0;
    end
  endgenerate

endmodule : data_cache_datapath_opt
