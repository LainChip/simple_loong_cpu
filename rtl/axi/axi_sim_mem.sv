`include "common.svh"
// Author: Dofingert
module axi_sim_mem#(
	parameter int valid_addr_len = 14
)(
	input clk, input rst_n,
	AXI_BUS.Slave slave
);

	logic [(1 << valid_addr_len) - 1 : 0][7:0]mem;

	logic req,we,useless_user;
	logic[31:0] addr,r_data,w_data;
	logic[3:0] byte_enable;

	// write logic
	always_ff @(posedge clk) begin : proc_mem
		// if(~rst_n) begin
		// 	mem <= '0;
		// end else 
		if(we) begin
			mem[{addr[valid_addr_len-1:2],2'b00}] <= (~byte_enable[0]) ? mem[{addr[valid_addr_len-1:2],2'b00}] : w_data[7:0];
			mem[{addr[valid_addr_len-1:2],2'b01}] <= (~byte_enable[1]) ? mem[{addr[valid_addr_len-1:2],2'b01}] : w_data[15:8];
			mem[{addr[valid_addr_len-1:2],2'b10}] <= (~byte_enable[2]) ? mem[{addr[valid_addr_len-1:2],2'b10}] : w_data[23:16];
			mem[{addr[valid_addr_len-1:2],2'b11}] <= (~byte_enable[3]) ? mem[{addr[valid_addr_len-1:2],2'b11}] : w_data[31:24];
		end
	end

	// read logic
	always_ff@(posedge clk) begin
		r_data <= {mem[{addr[valid_addr_len-1:2],2'b11}],mem[{addr[valid_addr_len-1:2],2'b10}],mem[{addr[valid_addr_len-1:2],2'b01}],mem[{addr[valid_addr_len-1:2],2'b00}]};
	end

	axi2mem#(
		.AXI_ID_WIDTH(4),
		.AXI_ADDR_WIDTH(32),
		.AXI_DATA_WIDTH(32),
		.AXI_USER_WIDTH(1)) axi2mem_ins(
		.clk_i (clk),.rst_ni(rst_n),
		.slave(slave),
		.req_o(req),
		.we_o(we),
		.addr_o(addr),
		.be_o(byte_enable),
		.user_o(useless_user),
		.data_o(w_data),
		.user_i('0),
		.data_i(r_data)
	);


endmodule
