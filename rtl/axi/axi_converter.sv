`include "common.svh"
`include "lsu_types.svh"

`ifdef __AXI_CONVERTER_VER_1

module axi_converter#(
    parameter int CACHE_PORT_NUM = 2
)(
    input clk,input rst_n,
	AXI_BUS.Master   axi_bus, // 来自pulp_axi 库
    input cache_bus_req_t  [CACHE_PORT_NUM - 1 : 0]req,       // cache的访问请求
    input cache_bus_resp_t [CACHE_PORT_NUM - 1 : 0]resp       // cache的访问应答
);

logic [2 * CACHE_PORT_NUM - 1 : 0]round_robin_mask;           // always keep this mask has CACHE_PORT_NUM enable
 

always_ff @(posedge clk) begin : proc_round_robin_status
	if(~rst_n) begin
		round_robin_status <= '0 | 1'b1;
	end else begin
		round_robin_status <= {round_robin_status[CACHE_PORT_NUM - 2 : 0],round_robin_status[CACHE_PORT_NUM - 1]};
	end
end



endmodule

`endif