`include "common.svh"

module reg_file #(
    parameter int DATA_WIDTH = 32,
    parameter int REG_FILE_SIZE = 32,
    parameter int REG_CONST_ZERO_SIZE = 1,
    parameter int REG_READ_PORT = 4,
    parameter int REG_WRITE_PORT = 2,
    parameter bit INNER_FORWARDING = 1,

    // DO NOT MODIFY
    parameter type dtype = logic [DATA_WIDTH-1:0],
    parameter type ptr_t = logic [$clog2(REG_FILE_SIZE) - 1 : 0] 
) (
    input clk,   // Clock
    input rst_n, // Asynchronous reset active low

    // READ PORT
    input  ptr_t [REG_READ_PORT - 1 : 0] r_ptr_i,
    output dtype [REG_READ_PORT - 1 : 0] r_data_o,

    // WRITE PORT
    input  ptr_t [REG_WRITE_PORT - 1 : 0] w_ptr_i,
    input  dtype [REG_WRITE_PORT - 1 : 0] w_data_i
);

    // 寄存器堆
    dtype [REG_FILE_SIZE - 1 : 0] regs,regs_update;

    // 读出逻辑
    generate
      for(genvar i = 0 ; i < REG_READ_PORT ; i+=1) begin
        if(INNER_FORWARDING) begin
          logic forwarding_enable;
          dtype forwarding_data;
          always_comb begin
            forwarding_enable = '0;
            forwarding_data = '0;
            for(integer j = 0 ; j < REG_WRITE_PORT ; j+=1) begin
              if(w_ptr_i[j] == r_ptr_i[i]) begin
                forwarding_enable |= 1'b1;
                forwarding_data   |= w_data_i[j];
              end
            end
          end
          assign r_data_o[i] = forwarding_enable ? forwarding_data : regs[r_ptr_i[i]];
        end else begin
          assign r_data_o[i] = regs[r_ptr_i[i]];           // 无内部转发
        end
      end
    endgenerate

    // 更新逻辑
    generate
      for(genvar i = 0 ; i < REG_FILE_SIZE; i+=1) begin
        if(i < REG_CONST_ZERO_SIZE) begin
          assign regs_update[i] = '0;
        end else begin
          logic we;
          dtype wdata;
          always_comb begin
            we = '0;
            wdata = '0;
            for(integer j = 0 ; j < REG_WRITE_PORT ; j+=1) begin
              if(w_ptr_i[j] == i[$clog2(REG_FILE_SIZE) - 1 : 0]) begin
                we |= 1'b1;
                wdata |= w_data_i[j];
              end
            end
          end
          assign regs_update[i] = we ? wdata : regs[i];
        end
      end
    endgenerate

    always_ff @(posedge clk) begin
      // if(~rst_n) begin
      //   regs <= '0;
      // end else
      begin
        regs <= regs_update;
      end
    end

endmodule : reg_file
