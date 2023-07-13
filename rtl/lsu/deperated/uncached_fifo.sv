`include "common.svh"

module uncached_fifo #(
    parameter int fifo_depth  = 16,
    parameter int data_length = 32
) (
    input clk,
    input rst_n,
    input r_valid,
    input w_valid,
    input [data_length - 1 : 0] data_in,
    output logic [data_length - 1 : 0] data_out,
    output full,
    output empty
);

  localparam int ptr_size = $clog2(fifo_depth);
  logic [ptr_size : 0] w_ptr;
  logic [ptr_size : 0] r_ptr;

  // Pointer controlling logic.
  always_ff @(posedge clk) begin
    if (~rst_n) begin
      w_ptr <= 0;
      r_ptr <= 0;
    end
    if (r_valid) begin
      r_ptr <= r_ptr + 1;
    end
    if (w_valid) begin
      w_ptr <= w_ptr + 1;
    end
  end

  logic ctrl_1, ctrl_2;
  assign ctrl_1 = w_ptr[ptr_size-1 : 0] == r_ptr[ptr_size-1 : 0];
  assign ctrl_2 = w_ptr[ptr_size] == r_ptr[ptr_size];
  assign full   = ctrl_1 && ~ctrl_2;
  assign empty  = ctrl_1 && ctrl_2;

  // Data controlling logic.
  logic [fifo_depth - 1 : 0][data_length - 1 : 0] data_bram;
  always_ff @(posedge clk) begin
    if (w_valid) begin
      data_bram[w_ptr[ptr_size-1 : 0]] <= data_in;
    end
  end
  always_ff @(posedge clk) begin
    if (r_valid) begin
      data_out <= data_bram[r_ptr[ptr_size-1 : 0]];
    end
  end

  // simpleDualPortRamRE #(
  //     .dataWidth(data_length),
  //     .ramSize  (fifo_depth),
  //     .latency  (1),
  //     .readMuler(1)
  // ) bram_core (
  //     .clk     (clk),
  //     .rst_n   (rst_n),
  //     .addressA(w_ptr[ptr_size-1 : 0]),
  //     .we      (w_valid),
  //     .addressB(r_ptr[ptr_size-1 : 0]),
  //     .re      (r_valid),
  //     .inData  (data_in),
  //     .outData (data_out)
  // );

endmodule
