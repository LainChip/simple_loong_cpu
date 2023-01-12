`timescale 1ns / 1ps

`include "types.svh"

module reg_file #(
    parameter int write_port_num = 2,
    parameter int read_port_num = 4,
    parameter int group = 1,

    parameter int reg_fileSize = 32,
    parameter int always_zero = 1,
    parameter int ptr_size = $clog2(reg_fileSize * group),
    parameter type ptr_t = logic [ptr_size - 1 : 0],  //HighestBit used To Hint Rename
    parameter int wptr_size = $clog2(reg_fileSize),
    parameter type wptr_t = logic [wptr_size - 1 : 0]
) (
    input clk,   // Clock
    input rst_n, // Asynchronous reset active low

    input logic [write_port_num * group - 1 : 0] we,
    input uint32_t [write_port_num * group - 1 : 0] w_data,
    output uint32_t [read_port_num - 1 : 0] r_data,

    input wptr_t [write_port_num * group - 1 : 0] w_addr,
    input ptr_t  [         read_port_num - 1 : 0] r_addr
);

  uint32_t [group * reg_fileSize - 1 : 0] reg_file, reg_file_new;

  always_comb //Port 0,1 for early Write, but 2,3 for delayed Write; Port 1 is superior than Port 0;
	begin
    reg_file_new = reg_file;
    for (int group_id = 0; group_id < group; group_id++)
      for (int i = always_zero; i < reg_fileSize; i++) begin
        for (int j = 0; j < write_port_num; j++) begin
          if (we[j+(group_id*write_port_num)] & (i == w_addr[j+(group_id*write_port_num)])) begin
            reg_file_new[i+(group_id*reg_fileSize)] = w_data[j+(group_id*write_port_num)];
          end
        end
      end
  end

  always_ff @(posedge clk) begin : proc_reg_file
    if (~rst_n) begin
      reg_file <= 0;  // A global reset is need for avoid 'x' in simulations.
    end else begin
      reg_file <= reg_file_new;
    end
  end

  // No Internal forwarding. all write should be pass by by-pass network
  for (genvar i = 0; i < read_port_num; i++) begin
    assign r_data[i] = reg_file[r_addr[i]];
  end

endmodule : reg_file
