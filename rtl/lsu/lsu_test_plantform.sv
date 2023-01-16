`include "common.svh"
`include "lsu_types.svh"
`include "decoder.svh"

module lsu_test_plantform (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low

	input write,
	input way_sel,
	input stall_req,
	input [31:0]w_data,
	input [31:0]addr,
	input [1:0] a_type,

	output [31:0]r_data,
	output pipe_stall
);
	logic[31:0] useless_data;
	logic[1:0][31:0]w_data_r;
	logic[1:0][31:0]p_addr;
	decode_info_t [1:0]decode_info;
	logic lsu_stall;

	cache_bus_req_t bus_req;
	cache_bus_resp_t bus_resp;

	AXI_BUS #(.AXI_ADDR_WIDTH(32),
		.AXI_ID_WIDTH  (4),
		.AXI_USER_WIDTH(1),
		.AXI_DATA_WIDTH(32)) mem_bus;

	always_ff @(posedge clk) begin : proc_w_data_r
		if(~rst_n) begin
			w_data_r <= '0;
			p_addr <= '0;
		end else if(~pipe_stall) begin
			w_data_r <= {w_data_r[0],w_data};
			p_addr <= {p_addr[0],addr};
		end
	end

	always_comb begin
		decode_info = '0;
		decode_info[way_sel].m1.mem_type = a_type;
		decode_info[way_sel].m1.mem_valid = 1'b1;
		decode_info[way_sel].m1.mem_write = write;
	end

	lsu lsu_ins(.clk,.rst_n,
		.decode_info_i(decode_info),
		.vaddr_i({addr,addr}),
		.paddr_i({p_addr[0],p_addr[0]}),
		.w_data_i({w_data_r[1],w_data_r[1]}),
		.r_data_o({r_data,useless_data}),

		.bus_req_o(bus_req),
		.bus_resp_i(bus_resp),

		.stall_i(stall_req),
		.busy_o(lsu_stall)
	);

	assign pipe_stall = lsu_stall | stall_req;

	axi_sim_mem sim_mem_ins(
		.clk(clk),.rst_n(rst_n),
		.slave(mem_bus)
	);

	axi_converter #(.CACHE_PORT_NUM(1))axi_converter(
		.clk(clk),.rst_n(rst_n),
		.axi_bus_if(mem_bus),
		.req_i(bus_req),
		.resp_o(bus_resp)
	);

endmodule
