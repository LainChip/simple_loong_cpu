`include "common.svh"
`include "decoder.svh"
`include "pipeline.svh"
`include "lsu_types.svh"
`include "bpu.svh"

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

	output logic [3:0] revert_vector_o,
	output logic ex_clr_req_o,
	output logic m1_clr_req_o,
	output logic m2_clr_req_o,

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
	output cache_bus_req_t bus_req_o,         // cache的访问请求
    input cache_bus_resp_t bus_resp_i,        // cache的访问应答
    input priv_resp_t priv_resp_i,
    output priv_req_t priv_req_o,
    output bpu_update_t bpu_feedback_o
);
	/*
		流水线寄存器定义及管理，包括数据转发
	*/
	ctrl_flow_t ex_ctrl_flow,m1_ctrl_flow,m2_ctrl_flow,wb_ctrl_flow;
	data_flow_t ex_data_flow_raw,ex_data_flow_forwarding,
			    m1_data_flow_raw,m1_data_flow_forwarding,
				m2_data_flow_raw,m2_data_flow_forwarding,
			    wb_data_flow;
	logic [31:0] alu_result;
	logic [31:0] bpf_result;
	logic [31:0] ex_vaddr;
	logic [31:0] m1_vaddr;
	logic [31:0] m2_paddr;

	logic [31:0] m2_csr_read, m2_lsu_read, m2_useless_data;

	// 数据转发
	for (genvar reg_id = 0; reg_id < 2; reg_id += 1) begin
		forwarding_unit#(
			.DATA_WIDTH(32),
			.SOURCE_NUM(3),
			.PIPE_NUM(2)
		)ex_forwarding(
			.pipe_sel_i(ex_ctrl_flow.forwarding_info[reg_id].forwarding_pipe_sel),
			.sel_vec_i(ex_ctrl_flow.forwarding_info[reg_id].ex_forward_source),
			.data_vec_i({forwarding_src_i[1][2],forwarding_src_i[1][1],forwarding_src_i[1][0],forwarding_src_i[0][2],forwarding_src_i[0][1],forwarding_src_i[0][0]}),
			.old_data_i(ex_data_flow_raw.reg_data[reg_id]),
			.new_data_o(ex_data_flow_forwarding.reg_data[reg_id])
		);
		forwarding_unit#(
			.DATA_WIDTH(32),
			.SOURCE_NUM(2),
			.PIPE_NUM(2)
		)m1_forwarding(
			.pipe_sel_i(m1_ctrl_flow.forwarding_info[reg_id].forwarding_pipe_sel),
			.sel_vec_i(m1_ctrl_flow.forwarding_info[reg_id].ex_forward_source),
			.data_vec_i({forwarding_src_i[1][2],forwarding_src_i[1][1],forwarding_src_i[0][2],forwarding_src_i[0][1]}),
			.old_data_i(m1_data_flow_raw.reg_data[reg_id]),
			.new_data_o(m1_data_flow_forwarding.reg_data[reg_id])
		);
		forwarding_unit#(
			.DATA_WIDTH(32),
			.SOURCE_NUM(1),
			.PIPE_NUM(2)
		)m2_forwarding(
			.pipe_sel_i(m2_ctrl_flow.forwarding_info[reg_id].forwarding_pipe_sel),
			.sel_vec_i(m2_ctrl_flow.forwarding_info[reg_id].ex_forward_source),
			.data_vec_i({forwarding_src_i[1][2],forwarding_src_i[0][2]}),
			.old_data_i(m2_data_flow_raw.reg_data[reg_id]),
			.new_data_o(m2_data_flow_forwarding.reg_data[reg_id])
		);
	end
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
			m2_paddr <= m1_vaddr;
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
	assign ex_data_flow_forwarding.result = ex_ctrl_flow.decode_info.wb.wb_sel == `_REG_WB_BPF ? bpf_result : alu_result;
	assign ex_data_flow_forwarding.pc = ex_data_flow_raw.pc;
	if(MAIN_PIPE) begin
		// BPF here
		bpf bpf_module(
			.clk,    // Clock DONT NEED
			.rst_n,  // Asynchronous reset active low
			.pc_i(ex_data_flow_forwarding.pc),
			.rj_i(ex_data_flow_forwarding.reg_data[1]),
			.rd_i(ex_data_flow_forwarding.reg_data[0]),
			.decode_i(ex_ctrl_flow.decode_info),
			.predict_i(ex_ctrl_flow.bpu_predict),
			.update_o(bpu_feedback_o)

		);
		assign ex_clr_req_o = bpu_feedback_o.flush;
		assign bpf_result = ex_data_flow_forwarding.pc + 32'd4;
	end else begin
		assign ex_clr_req_o = 0;
		assign bpf_result = 32'd0;
	end
	assign ex_stall_req_o = '0;

	// AGU here
	assign ex_vaddr = ex_data_flow_forwarding.reg_data[1] + {{20{ex_ctrl_flow.decode_info.general.inst25_0[21]}},ex_ctrl_flow.decode_info.general.inst25_0[21:10]};

	assign m1_stall_req_o = '0;
	assign m1_clr_req_o = '0;

	if(MAIN_PIPE) begin
		// Mem 1 部分，准备读取Tag和Data的地址，进行TLB第二阶段比较。 （转发源）
		// Mem connection here
		// Mem 2 部分，TLB结果返回paddr，比较Tag，产生结果，对CSR堆进行控制。 
		// Mem connection here
		lsu lsu_module(.clk,.rst_n,
			.decode_info_i(m1_ctrl_flow.decode_info),
			.vaddr_i({'0,m1_vaddr}),
			.paddr_i({'0,m2_paddr}),
			.w_data_i({32'd0,m2_data_flow_forwarding.reg_data[0]}),
			.r_data_o({m2_useless_data,m2_lsu_read}),

			.bus_req_o(bus_req_o),
			.bus_resp_i(bus_resp_i),

			.stall_i(|stall_vec_i[2:1]),
			.busy_o(m2_stall_req_o)
		);
		// CSR connection here
		csr csr_module(
	    .clk,
	    .rst_n,
	    .decode_info_i(m2_ctrl_flow.decode_info),     //输入：解码信息
	    .stall_i(stall_vec_i[2]),           //输入：流水线暂停
	    .instr_i(m2_ctrl_flow.decode_info.general.inst25_0),           //输入：指令后26位
	    //for read
	    .rd_data_o(m2_csr_read),         //输出：读数据
	    // for write
	    .wr_data_i(m2_data_flow_forwarding.reg_data[0]),          //输入：写数据
	    .wr_mask_i(m2_data_flow_forwarding.reg_data[1]),          //输入：rj寄存器存放的写掩码
	    //for interrupt
	    .interrupt_i('0 /*TODO*/),        //输入：中断信号
	    //for exception
	    .ecode_i('0 /*TODO*/),            //输入：两条流水线的例外一级码
	    .esubcode_i('0 /*TODO*/),         //输入：两条流水线的例外二级码
	    .excp_trigger_i('0 /*TODO*/),     //输入：发生异常的流水级
	    .bad_va_i('0 /*TODO*/),           //输入：地址相关例外出错的虚地址
	    .instr_pc_i(m2_data_flow_forwarding.pc),         //输入：指令pc
	    .do_redirect_o(/*TODO NOT CONNECTED*/),      //输出：是否发生跳转
	    .redirect_addr_o(/*TODO NOT CONNECTED*/),    //输出：返回或跳转的地址
	    //todo：tlb related exceptions
	    // timer
	    .timer_data_o(/*TODO NOT CONNECTED*/),                //输出：定时器值
	    .tid_o(/*TODO NOT CONNECTED*/)                        //输出：定时器id
	    //todo: llbit
	    //todo: tlb related addr translate
		);
		assign m2_clr_req_o = '0;
	end else begin
		assign m2_lsu_read = '0;
		assign m2_csr_read = '0;
		assign m2_clr_req_o = '0;
	end
	assign m1_data_flow_forwarding.result = m1_data_flow_raw.result;
	assign m1_data_flow_forwarding.pc = m1_data_flow_raw.pc;
	assign m2_data_flow_forwarding.result = (m2_ctrl_flow.decode_info.wb.wb_sel == `_REG_WB_ALU || 
											 m2_ctrl_flow.decode_info.wb.wb_sel == `_REG_WB_BPF) ? m2_data_flow_raw.result:
	(m2_ctrl_flow.decode_info.wb.wb_sel == `_REG_WB_LSU ? m2_lsu_read : m2_csr_read);
	assign m2_data_flow_forwarding.pc = m2_data_flow_raw.pc;
	// WB部分，选择写回源进行写回。（转发源）
	assign reg_w_addr_o = wb_ctrl_flow.w_reg;
	assign reg_w_data_o = wb_data_flow.result;

	// revert 信号生成
	assign revert_vector_o = {wb_ctrl_flow.revert,m2_ctrl_flow.revert,m1_ctrl_flow.revert,ex_ctrl_flow.revert};

endmodule : backend_pipeline