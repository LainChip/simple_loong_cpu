module fast_mimo_fifo #(
	parameter int DATA_WIDTH = 32,
	// parameter int DEPTH = 8,
	// parameter int BANK = 4,
	// parameter int WRITE_PORT = 2,
	// parameter int READ_PORT = 2,
	parameter type dtype = logic [DATA_WIDTH-1:0]
)(
	input clk,
	input rst_n,

	input flush_i,

	input logic [1: 0] write_valid_i,

	output logic [1: 0] write_num_o,
	input dtype [1 : 0] write_data_i,

	output logic [1 : 0] read_valid_o,
	input logic [1 : 0] issue_i,
	output dtype [1 : 0] read_data_o
);

assign write_ready_o = 1'b1;
(*MAX_FANOUT=70*) dtype[1:0] read_data;
  (*MAX_FANOUT=70*) logic[1:0] read_valid;
  always_ff @(posedge clk) begin
    if(flush_i || ~rst_n) begin
      read_valid_o <= '0;
    end else begin
      read_valid_o <= read_valid;
    end
    read_data_o <= read_data;
  end
  always_comb begin
    write_num_o      = '0;
    read_valid = read_valid_o;
    read_data  = read_data_o;
    unique casez({read_valid_o, write_valid_i, issue_i})
      // NO VALID INST YET
      6'b00???? : begin
        read_valid        = write_valid_i;
        write_num_o       = write_valid_i[0] + write_valid_i[1];
        read_data = write_data_i;
      end
      // HAS ONE VALID INST
      6'b01?0?0 : begin
        read_valid = 2'b01;
      end
      6'b01?0?1 : begin
        read_valid = '0;
      end
      6'b01?1?0 : begin
        read_valid           = 2'b11;
        read_data[1] = write_data_i[0];
        write_num_o          = 1;
      end
      6'b01?1?1 : begin
        read_valid           = 2'b01;
        read_data[0] = write_data_i[0];
        write_num_o          = 1;
      end
      // HAS TWO VALID INST
      6'b1???00 : begin
        read_valid = 2'b11;
      end
      6'b1?0001 : begin
        read_valid           = 2'b01;
        read_data[0] = read_data_o[1];
      end
      6'b1?001? : begin
        read_valid = 2'b00;
      end
      6'b1?0101 : begin
        read_valid           = 2'b11;
        read_data[0] = read_data_o[1];
        read_data[1] = write_data_i[0];
        write_num_o          = 1;
      end
      6'b1?011? : begin
        read_valid           = 2'b01;
        read_data[0] = write_data_i[0];
        write_num_o          = 1;
      end
      6'b1?1?01 : begin
        read_valid           = 2'b11;
        read_data[0] = read_data_o[1];
        read_data[1] = write_data_i[0];
        write_num_o          = 1;
      end
      6'b1?1?1? : begin
        read_valid           = 2'b11;
        read_data[0] = write_data_i[0];
        read_data[1] = write_data_i[1];
        write_num_o          = 2;
      end
    endcase
  end

endmodule
