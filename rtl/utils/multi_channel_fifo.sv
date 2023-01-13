`include "common.svh"

module multi_channel_fifo #(
	parameter int DATA_WIDTH = 32,
	parameter int DEPTH = 4,
	parameter int BANK = 4,
	parameter int WRITE_PORT = 2,
	parameter int READ_PORT = 2,
	parameter type dtype = logic [DATA_WIDTH-1:0]
)(
	input clk,
	input rst_n,

	input flush_i,

	input logic write_valid_i,
	output logic write_ready_o,
	input logic [$clog2(WRITE_PORT + 1) - 1: 0] write_num,
	input dtype [WRITE_PORT - 1 : 0] write_data_i,

	output logic [READ_PORT - 1 : 0] read_valid_o,
	input logic read_ready_i,
	input logic [$clog2(READ_PORT + 1) - 1 : 0] read_num,
	output dtype [READ_PORT - 1 : 0] read_data_o
);

	typedef logic [$clog2(BANK) - 1 : 0] ptr_t;

	ptr_t [BANK - 1 : 0] read_index,write_index,port_read_index,port_write_index;
	logic [BANK - 1 : 0] fifo_full,fifo_empty,fifo_push,fifo_pop;
	dtype [CHANNEL-1:0] data_in, data_out;
	logic [$clog2(BANK + 1) - 1 : 0] count_full;
	assign write_ready_o = count_full <= (BANK - WRITE_PORT);

	// FIFO 部分
	generate
		for(genvar i = 0 ; i < BANK; i += 1) begin
			// 指针更新策略
			always_ff @(posedge clk) begin : proc_read_index
				if(~rst_n || flush_i) begin
					read_index[i] <= i % BANK;
				end else begin
					if(read_ready_i)
						read_index[i] <= read_index[i] + read_num;
				end
			end
			always_ff @(posedge clk) begin : proc_write_index
				if(~rst_n || flush_i) begin
					write_index[i] <= i;
				end else begin
					if(write_valid_i & write_ready_o)
						write_index[i] <= write_index[i] + write_num;
				end
			end
			always_ff @(posedge clk) begin : proc_port_read_index
				if(~rst_n || flush_i) begin
					port_read_index[i] <= (BANK - i) % BANK;
				end else begin
					if(read_ready_i)
						port_read_index[i] <= port_read_index[i] - read_num;
				end
			end
			always_ff @(posedge clk) begin : proc_port_write_index
				if(~rst_n || flush_i) begin
					port_write_index[i] <= (BANK - i) % BANK;
				end else begin
					if(write_valid_i & write_ready_o)
						port_write_index[i] <= port_write_index[i] - write_num;
				end
			end

			// FIFO 控制信号
			assign fifo_pop[i] = port_read_index[i] < read_num;
			assign fifo_push[i] = port_write_index[i] < write_num;
			assign data_in[i] = write_data_i[port_write_index[i] & (WRITE_PORT - 1)];

			// FIFO 生成
			fifo_v3 #(
				.DEPTH       (DEPTH),
				.DATA_WIDTH  (DATA_WIDTH),
				.dtype       (dtype)
			) instr_fifo (
				.clk         (clk     ),
				.rst_n       (rst_n   ),
				.flush_i     (flush_i ),
				.full_o      (fifo_full[i]),
				.empty_o     (fifo_empty[i]),
				.usage_o     (/* empty */),
				.data_i      (data_in[i]),
				.data_o      (data_out[i]),
				.push_i      (write_valid_i & fifo_push[i]),
				.pop_i       (read_ready_i  & fifo_pop[i])
			);
		end
	endgenerate

	// 输出部分
	generate
		for(genvar i = 0 ; i < READ_PORT; i+= 1) begin
			assign read_data_o[i] = data_out[port_read_index[i]];
			assign read_valid_o[i] = ~fifo_empty[port_read_index[i]];
		end
	endgenerate

endmodule