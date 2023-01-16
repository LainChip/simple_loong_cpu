`include "common.svh"
`include "decoder.svh"
`include "pipeline.svh"

module backend_pipeline #(
	parameter bit MAIN_PIPE = 1'b1
)(
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low

	// 控制用暂停信号
	input logic [2:0] stall_vec_i, // 0 for ex, 1 for m1, 2 for m2
	input logic [2:0] clr_vec_i,   // 0 for ex, 1 for m1, 2 for m2

	// 暂停请求
	output logic ex_stall_req_o,
	output logic m1_stall_req_o,
	output logic m2_stall_req_o,

	input logic revert_i,
	input logic issue_i,
	ctrl_flow_t ctrl_flow_i,
	data_flow_t data_flow_i,

	// FORWARDING DATA SOURCE
	input logic[1:0][2:0][31:0] forwarding_src_i,

	// FORWARDING DATA OUTPUT
	output logic[2:0] forwarding_data_o,

	output logic[4:0]  reg_w_addr_o,
	output logic[31:0] reg_w_data_o,
	
	// FOR MAIN PIPE
	output cache_bus_req_t bus_req_o,       // cache的访问请求
    input cache_bus_resp_t bus_resp_i        // cache的访问应答
    input priv_resp_t priv_resp_i,
    output priv_req_t priv_req_o,
    output bpu_update_t bpu_feedback_o,

);
	/*
		流水线寄存器定义及管理，包括数据转发
	*/
	ctrl_flow_t ex_ctrl_flow,m1_ctrl_flow,m2_ctrl_flow,wb_ctrl_flow;
	data_flow_t ex_data_flow_raw,ex_data_flow_forwarding,
			    m1_data_flow_raw,m2_data_flow_forwarding,
			    wb_data_flow;
	logic [31:0] alu_result;
	logic [31:0] ex_vaddr;
	logic [31:0] m1_vaddr;

	// 数据转发

	// 控制寄存器
	always_ff @(posedge clk) begin
		if(~rst_n) begin
			ex_ctrl_flow <= '0;
		end else if(~stall_vec_i[0]) begin
			if(issue_i) begin
				ex_ctrl_flow <= ctrl_flow_i;
			end else begin
				ex_ctrl_flow <= '0;
			end
		end
	end
	always_ff @(posedge clk) begin
		if(~rst_n) begin
			m1_ctrl_flow <= '0;
		end else if(~stall_vec_i[1]) begin
			if(clr_vec_i[0]) begin
				m1_ctrl_flow <= '0;
			end else begin
				m1_ctrl_flow <= ex_ctrl_flow;
			end
		end
	end
	always_ff @(posedge clk) begin
		if(~rst_n) begin
			m2_ctrl_flow <= '0;
		end else if(~stall_vec_i[2]) begin
			if(clr_vec_i[1]) begin
				m2_ctrl_flow <= '0;
			end else begin
				m2_ctrl_flow <= m1_ctrl_flow;
			end
		end
	end
	always_ff @(posedge clk) begin
		if(~rst_n) begin
			wb_ctrl_flow <= '0;
		end else begin
			if(clr_vec_i[2]) begin
				wb_ctrl_flow <= '0;
			end else begin
				wb_ctrl_flow <= m2_ctrl_flow;
			end
		end
	end

	// 数据寄存器
	always_ff @(posedge clk) begin
		if(~stall_vec_i[0]) begin
			ex_data_flow_raw <= data_flow_i;
		end else begin
			ex_data_flow_raw <= ex_data_flow_forwarding;
		end
	end
	always_ff @(posedge clk) begin
		if(~stall_vec_i[1]) begin
			m1_data_flow_raw <= ex_data_flow_forwarding;
			m1_vaddr <= ex_vaddr;
		end else begin
			m1_data_flow_raw <= m1_data_flow_forwarding;
		end
	end
	always_ff @(posedge clk) begin
		if(~stall_vec_i[2]) begin
			m2_data_flow_raw <= m1_data_flow_forwarding;
		end else begin
			m2_data_flow_raw <= m2_data_flow_forwarding;
		end
	end
	always_ff @(posedge clk) begin
		wb_data_flow <= m2_data_flow_forwarding;
	end

	// Excute 部分，对计算和跳转指令进行执行，对访存地址进行计算并完成第一阶段TLB比较 
	// ALU here
	alu alu_module(
    .decode_info_i(ex_ctrl_flow.decode_info),
    .reg_fetch_i(ex_data_flow_forwarding.reg_data),
    .pc_i(ex_data_flow_forwarding.pc),
    .alu_res_o(alu_result)
	);
	assign ex_data_flow_forwarding.result = alu_result;

	// BPF here
	bpf bpf_module(
	.clk,    // Clock DONT NEED
	.rst_n,  // Asynchronous reset active low
	.pc_i(ex_data_flow_forwarding.pc),
	.rj_i(ex_data_flow_forwarding.reg_data[1]),
	.rd_i(ex_data_flow_forwarding.reg_data[0]),
	.decode_i(ex_ctrl_flow.decode_info),
	.predict_i(ex_ctrl_flow.bpu_predict),
	.update_o(bpu_feedback_o),
	.target_o(/*NOT CONNECT*/)
	);

	// AGU here
	assign ex_vaddr = ex_data_flow_forwarding.reg_data[1] + {{20{ex_ctrl_flow.decode_info.general.inst25_0[21]}},ex_ctrl_flow.decode_info.general.inst25_0[21:10]};

	// Mem 1 部分，准备读取Tag和Data的地址，进行TLB第二阶段比较。 （转发源）
	// Mem connection here
	// Mem 2 部分，TLB结果返回paddr，比较Tag，产生结果，对CSR堆进行控制。 
	// Mem connection here
	lsu lsu_ins(.clk,.rst_n,
		.decode_info_i(m1_ctrl_flow.decode_info),
		.vaddr_i({'0,m1_vaddr}),
		.paddr_i({'0,m2_p_addr}),
		.w_data_i({32'd0,mem_w_data}),
		.r_data_o({useless_data,m2_r_data}),

		.bus_req_o(bus_req_o),
		.bus_resp_i(bus_resp_i),

		.stall_i(|stall_vec_i[2:1]),
		.busy_o(m2_stall_req_o)
	);


	// CSR connection here
	

	// WB部分，选择写回源进行写回。（转发源）

endmodule : backend_pipeline