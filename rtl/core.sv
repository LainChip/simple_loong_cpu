`include "common.svh"
`include "pipeline.svh"

module cpu_core(
    input clk,
    input rst_n,
    input [7:0] int_i,
    AXI_BUS.Slave mem_bus
);

	inst_t 		     [1:0]inst;
	logic  		     [1:0]inst_valid;
	logic  		     [1:0]issue_num;
	logic  		     backend_stall;
	bpu_update_t     bpu_feedback;
	priv_req_i   	 priv_req;
	priv_resp_o      priv_resp;
	cache_bus_req_t	 ibus_req , dbus_req;
	cache_bus_resp_t ibus_resp, dbus_resp;

    // axi converter
    axi_converter #(.CACHE_PORT_NUM(2))axi_converter(
		.clk(clk),.rst_n(rst_n),
		.axi_bus_if(mem_bus),
		.req_i({dbus_req,ibus_req}),
		.resp_o({dbus_resp,ibus_resp})
	);

    // frontend
    frontend frontend(
	.clk,
	.rst_n,

	// 指令输出
	.inst_o(inst),
	.inst_valid_o(inst_valid),
	.issue_num_i(issue_num), // 0, 1, 2
	.backend_stall_i(backend_stall), 

	// BPU 反馈
	.bpu_feedback_i(bpu_feedback),

    // 特权控制信号
    .priv_resp_o(priv_resp),
    .priv_req_i(priv_req),

	// 访存总线
    .bus_req_o(ibus_req),       // cache的访问请求
    .bus_resp_i(ibus_resp)      // cache的访问应答
	);

    // backend
    backend backend(
	.clk,
	.rst_n,

	// 指令输入
	.inst_i(inst),
	.inst_valid_i(inst_valid),
	.issue_num_o(issue_num), // 0, 1, 2
	.backend_stall_o(backend_stall), 

	// BPU 输入（随指令走）
	// input bpu_predict_t [1:0] bpu_predict_i,
	.bpu_feedback_o(bpu_feedback),

    // 特权控制信号
    .priv_resp_i(priv_resp),
    .priv_req_o(priv_req),

	// 访存总线
    .bus_req_o(dbus_req),       // cache的访问请求
    .bus_resp_i(dbus_resp)      // cache的访问应答


);

endmodule