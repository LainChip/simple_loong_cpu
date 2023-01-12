`timescale 1ns / 1ps

`include "types.svh"
`include "issue.svh"

module inst_fifo #(
    parameter int depth = 4,
    parameter int data_size = 32
) (
    input clk,   // Clock`
    input rst_n, // Asynchronous reset active low

    //input valid_input,
    input valid_first,
    input valid_second,
    input logic [31:3] in_address,
    input logic [1:0][data_size - 1 : 0] in,
    output logic [1:0][data_size - 1 : 0] out,
    output logic [1:0][31:2] out_address,
    output logic [1:0] valid_out,
    output logic fifo_full,

    input read_one,
    input read_two,
    input jClr,
    input uint32_t jAddress
);

  logic miss_r;
  always_ff @(posedge clk) begin
    miss_r <= jClr;
  end

  //assign correct_address = ref_address[31:3]== in.inst[0].address[31:3];
  logic allow_to_input;
  assign allow_to_input = ~fifo_full;
  logic valid_one;
  logic valid_two;
  assign valid_two   = valid_first & valid_second/*(~ref_address[2])*/;
  assign valid_one   = valid_first ^ valid_second/*ref_address[2]*/;

  localparam ptr_size = $clog2(depth);

  typedef logic [ptr_size : 0] ptr_t;

  typedef struct packed {
    logic [31:2] pc;
    logic [data_size - 1 : 0] content;
  } fifo_content_t;

  fifo_content_t [1:0] in_elem;
  assign in_elem[0].pc = {in_address, 1'b0};
  assign in_elem[0].content = in[0];
  assign in_elem[1].pc = {in_address, 1'b1};
  assign in_elem[1].content = in[1];

  fifo_content_t [depth - 1 : 0] fifo;

  // write logic
  ptr_t w_ptr_1;
  ptr_t w_ptr_2;
  logic write_one;
  assign write_one = allow_to_input & valid_one;
  logic write_two;
  assign write_two = allow_to_input & valid_two;
  always_ff @(posedge clk) begin : proc_fifo
    if (~rst_n) begin
      fifo <= 0;
    end else begin
      if (write_one) begin
        if(valid_first)
          fifo[w_ptr_1[ptr_size-1 : 0]] <= in_elem[0];
        else
          fifo[w_ptr_1[ptr_size-1 : 0]] <= in_elem[1];
      end else if (write_two) begin
        fifo[w_ptr_1[ptr_size-1 : 0]] <= in_elem[0];
        fifo[w_ptr_2[ptr_size-1 : 0]] <= in_elem[1];
      end
    end
  end

  ptr_t next_w_ptr;
  assign next_w_ptr = w_ptr_2 + 1;
  always_ff @(posedge clk) begin : proc_w_ptr
    if (~rst_n | jClr) begin
      w_ptr_1 <= 0;
      w_ptr_2 <= 1;
    end else begin
      if (write_one) begin
        w_ptr_1 <= w_ptr_2;
        w_ptr_2 <= next_w_ptr;
      end else if (write_two) begin
        w_ptr_1 <= next_w_ptr;
        w_ptr_2 <= w_ptr_2 + 2;
      end
    end
  end

  // read logic
  ptr_t r_ptr_1;
  ptr_t r_ptr_2;
  ptr_t next_r_ptr;
  assign next_r_ptr = r_ptr_2 + 1;
  always_ff @(posedge clk) begin : proc_r_ptr
    if (~rst_n | jClr) begin
      r_ptr_1 <= 0;
      r_ptr_2 <= 1;
    end else begin
      if (read_one) begin
        r_ptr_1 <= r_ptr_2;
        r_ptr_2 <= next_r_ptr;
      end else if (read_two) begin
        r_ptr_1 <= next_r_ptr;
        r_ptr_2 <= r_ptr_2 + 2;
      end
    end
  end
  assign out_address[0] = {fifo[r_ptr_1[ptr_size-1 : 0]].pc};
  assign out_address[1] = {fifo[r_ptr_2[ptr_size-1 : 0]].pc};
  assign out[0] = fifo[r_ptr_1[ptr_size-1 : 0]].content;
  assign out[1] = fifo[r_ptr_2[ptr_size-1 : 0]].content;

  // Valid logic
  ptr_t fifo_count_0;
  ptr_t fifo_count_1;
  assign fifo_count_0 = w_ptr_1 - r_ptr_1;
  assign fifo_count_1 = w_ptr_1 - r_ptr_2;
  assign valid_out[0] = (|fifo_count_0);
  assign valid_out[1] = (|fifo_count_1[ptr_size-1 : 0]) & (~fifo_count_1[ptr_size]);

  assign fifo_full = fifo_count_0[ptr_size] | (&fifo_count_0[ptr_size-1 : 0]);

endmodule : inst_fifo
