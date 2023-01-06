`include "common.svh"
`include "lsu_types.svh"

`ifdef __AXI_CONVERTER_VER_1

module axi_converter#(
    parameter int CACHE_PORT_NUM = 2
)(
    input clk,input rst_n,
	AXI_BUS.Master   axi_bus_if, // 来自pulp_axi 库
    input cache_bus_req_t  [CACHE_PORT_NUM - 1 : 0]req_i,       // cache的访问请求
    output cache_bus_resp_t [CACHE_PORT_NUM - 1 : 0]resp_o       // cache的访问应答
);

endmodule

`endif