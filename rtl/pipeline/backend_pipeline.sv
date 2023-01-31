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
    input [7:0] int_i,

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
	output logic m2_clr_exclude_self_o,

	input logic revert_i,
	input logic issue_i,
	ctrl_flow_t ctrl_flow_i,
	data_flow_t data_flow_i,

	// FORWARDING DATA SOURCE
	input logic[1:0][2:0][31:0] forwarding_src_i,

	// FORWARDING DATA OUTPUT
	output logic[2:0][31:0] forwarding_data_o,

	output logic[4:0]  reg_w_addr_o,
	output logic[31:0] reg_w_data_o,
	
	output logic[63:0] timer_data_o,
	output logic[31:0] tid_o,

	// FOR MAIN PIPE
	output cache_bus_req_t bus_req_o,         // cache的访问请求
    input cache_bus_resp_t bus_resp_i,        // cache的访问应答
    input priv_resp_t priv_resp_i,
    output priv_req_t priv_req_o,
    output bpu_update_t bpu_feedback_o,
	
	// MMU 访问信号
	output mmu_s_req_t mmu_req_o,			  // attached in m1
	input mmu_s_resp_t mmu_resp_i,		      // response in m1

	input tlb_entry_t tlb_entry_i

    `ifdef _DIFFTEST_ENABLE
    ,input logic delay_csr_i
    `endif
);
	/*
		流水线寄存器定义及管理，包括数据转发
	*/
	ctrl_flow_t ex_ctrl_flow,m1_ctrl_flow,m2_ctrl_flow,wb_ctrl_flow;
	excp_flow_t ex_excp_flow,m1_excp_flow,m2_excp_flow;
	data_flow_t ex_data_flow_raw,ex_data_flow_forwarding,
			    m1_data_flow_raw,m1_data_flow_forwarding,
				m2_data_flow_raw,m2_data_flow_forwarding,
			    wb_data_flow;

	logic [18:0] m2_csr_vppn;

	logic [31:0] alu_result;
	logic [31:0] bpf_result;
	logic [31:0] ex_vaddr;
	logic [31:0] m1_saddr,m1_paddr,m1_word_shift;
	logic [31:0] m2_paddr;

	logic [31:0] m2_csr_read, m2_lsu_read, m2_csr_jump_target, m2_vaddr;
	
	mmu_s_resp_t m2_mmu_resp;
	logic m2_csr_jump_req,m2_lsu_clr_hint;
	logic m1_lsu_ale;

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
			.sel_vec_i(m1_ctrl_flow.forwarding_info[reg_id].m1_forward_source),
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
			.sel_vec_i(m2_ctrl_flow.forwarding_info[reg_id].m2_forward_source),
			.data_vec_i({forwarding_src_i[1][2],forwarding_src_i[0][2]}),
			.old_data_i(m2_data_flow_raw.reg_data[reg_id]),
			.new_data_o(m2_data_flow_forwarding.reg_data[reg_id])
		);
	end
	// 控制寄存器
	always_ff @(posedge clk) begin
		if(~rst_n) begin
			ex_ctrl_flow <= '0;
			ex_excp_flow <= '0;
		end else if(~stall_vec_i[0]) begin
			if(issue_i) begin
				ex_ctrl_flow <= ctrl_flow_i;
			end else begin
				ex_ctrl_flow <= '0;
			end
		end else begin
			// 在暂停的情况下，需要依据管线的整体暂停情况，对转发向量进行处理
			for(integer i = 0 ; i < 2 ; i += 1) begin
				if((~stall_vec_i[1] & ex_ctrl_flow.forwarding_info[i].ex_forward_source[1]) | (~stall_vec_i[2] & ex_ctrl_flow.forwarding_info[i].ex_forward_source[2]) | (ex_ctrl_flow.forwarding_info[i].ex_forward_source[3])) begin
					ex_ctrl_flow.forwarding_info[i].ex_forward_source <= {ex_ctrl_flow.forwarding_info[i].ex_forward_source[2:1],1'b0, ~|ex_ctrl_flow.forwarding_info[i].ex_forward_source[2:1]};
					ex_ctrl_flow.forwarding_info[i].m1_forward_source <= {ex_ctrl_flow.forwarding_info[i].m1_forward_source[1],1'b0,~ex_ctrl_flow.forwarding_info[i].m1_forward_source[1]};
					ex_ctrl_flow.forwarding_info[i].m2_forward_source <= 2'b01;
				end
			end
		end
	end
	always_ff @(posedge clk) begin
		if(~rst_n) begin
			m1_ctrl_flow <= '0;
			m1_excp_flow <= '0;
		end else if(~stall_vec_i[1]) begin
			if(clr_vec_i[0]) begin
				m1_ctrl_flow <= '0;
				m1_excp_flow <= '0;
			end else begin
				m1_ctrl_flow <= ex_ctrl_flow;
				m1_excp_flow.adef <= ex_ctrl_flow.fetch_excp.adef; 
			end
		end else begin
			// 在暂停的情况下，需要依据管线的整体暂停情况，对转发向量进行处理
			for(integer i = 0 ; i < 2 ; i += 1) begin
				if((~stall_vec_i[2] & m1_ctrl_flow.forwarding_info[i].m1_forward_source[1]) | (m1_ctrl_flow.forwarding_info[i].m1_forward_source[2])) begin
					m1_ctrl_flow.forwarding_info[i].m1_forward_source <= {m1_ctrl_flow.forwarding_info[i].m1_forward_source[1],1'b0,~m1_ctrl_flow.forwarding_info[i].m1_forward_source[1]};
					m1_ctrl_flow.forwarding_info[i].m2_forward_source <= 2'b01;
				end
			end
		end
	end
	always_ff @(posedge clk) begin
		if(~rst_n) begin
			m2_ctrl_flow <= '0;
			m2_excp_flow <= '0;
		end else if(~stall_vec_i[2]) begin
			if(clr_vec_i[1]) begin
				m2_ctrl_flow <= '0;
				m2_excp_flow <= '0;
			end else begin
				m2_mmu_resp <= mmu_resp_i;
				m2_ctrl_flow <= m1_ctrl_flow;
				m2_excp_flow.adef <= m1_excp_flow.adef;
				m2_excp_flow.ale  <= m1_lsu_ale;
			end
		end else begin
			// 在暂停的情况下，需要依据管线的整体暂停情况，对转发向量进行处理
			for(integer i = 0 ; i < 2 ; i += 1) begin
				if(m2_ctrl_flow.forwarding_info[i].m2_forward_source[1]) begin
					m2_ctrl_flow.forwarding_info[i].m2_forward_source <= 2'b01;
				end
			end
		end
	end
	always_ff @(posedge clk) begin
		if(~rst_n) begin
			wb_ctrl_flow <= '0;
		end else begin
			if(clr_vec_i[2] | stall_vec_i[2]) begin
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
			if(ex_ctrl_flow.decode_info.m2.tlbsrch_en) begin
				m1_saddr <= {m2_csr_vppn, 13'd0};
			end else begin
				m1_saddr <= ex_vaddr;
			end
			m1_word_shift <= ex_vaddr[1:0];
			m2_paddr <= m1_paddr;
		end else begin
			m1_data_flow_raw <= m1_data_flow_forwarding;
		end
	end
	assign m1_paddr = mmu_resp_i.paddr;
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
    .reg_fetch_i({ex_data_flow_forwarding.reg_data[0],ex_data_flow_forwarding.reg_data[1]}),
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
			.csr_flush_i(m2_csr_jump_req),
			.stall_i(stall_vec_i[0]),
			.pc_i(ex_data_flow_forwarding.pc),
			.rj_i(ex_data_flow_forwarding.reg_data[1]),
			.rd_i(ex_data_flow_forwarding.reg_data[0]),
			.csr_target_i(m2_csr_jump_target),
			.decode_i(ex_ctrl_flow.decode_info),
			.predict_i(ex_ctrl_flow.bpu_predict),
			.update_o(bpu_feedback_o),

		);
		assign ex_stall_req_o = ex_ctrl_flow.decode_info.m2.tlbsrch_en & (m1_ctrl_flow.decode_info.is.pipe_one_inst | (m2_ctrl_flow.decode_info.is.pipe_one_inst & stall_vec_i[2])); // ex级的TLBSRCH 需要等待 m1 m2处 可能对tlb存在修改的指令执行完成。
		assign ex_clr_req_o = bpu_feedback_o.flush;
		assign bpf_result = ex_data_flow_raw.pc + 32'd4;
	end else begin
		assign ex_stall_req_o = '0;
		assign ex_clr_req_o = 0;
		assign bpf_result = 32'd0;
	end


	assign m1_stall_req_o = '0;
	assign m1_clr_req_o = '0;

	if(MAIN_PIPE) begin	: sp_inst_blk
		// AGU here
		assign ex_vaddr = ex_data_flow_forwarding.reg_data[1] + {{20{ex_ctrl_flow.decode_info.general.inst25_0[21]}},ex_ctrl_flow.decode_info.general.inst25_0[21:10]};

		// 地址检查
		assign m1_lsu_ale = ((|m1_word_shift) & m1_ctrl_flow.decode_info.m1.mem_type[0] & ~m1_ctrl_flow.decode_info.m1.mem_type[1]) 
		|| ((m1_word_shift[0]) & ~m1_ctrl_flow.decode_info.m1.mem_type[0] & m1_ctrl_flow.decode_info.m1.mem_type[1]);

		// Mem 2 部分，TLB结果返回paddr，比较Tag，产生结果，对CSR堆进行控制。 
		// Mem connection here
		lsu lsu_module(.clk,.rst_n,
			.decode_info_i(ex_ctrl_flow.decode_info),
			.request_valid_i(~stall_vec_i[0]),
			.vaddr_i(ex_vaddr),
			.vaddr_o(m2_vaddr),
			.paddr_i(m1_paddr),
			.w_data_i(m2_data_flow_forwarding.reg_data[0]),
			.request_clr_m2_i(clr_vec_i[2] | m2_lsu_clr_hint),
			.request_clr_m1_i(clr_vec_i[1]),
			.r_data_o(m2_lsu_read),

			.bus_req_o(bus_req_o),
			.bus_resp_i(bus_resp_i),

			.stall_i(|stall_vec_i[2:1]),
			.busy_o(m2_stall_req_o)
		);
		// CSR connection here
		logic [5:0]  ecode;
		logic [8:0]  esubcode;
		logic        excp_trigger;
		logic [31:0] bad_va;
		csr csr_module(
			.clk,
			.rst_n,
			.decode_info_i(m2_ctrl_flow.decode_info),     //输入：解码信息
			.excp_i(m2_excp_flow),
			.stall_i(stall_vec_i[2]),           //输入：流水线暂停
			.instr_i(m2_ctrl_flow.decode_info.general.inst25_0),           //输入：指令后26位
			//for read
			.rd_data_o(m2_csr_read),         //输出：读数据
			// for write
			.wr_data_i(m2_data_flow_forwarding.reg_data[0]),          //输入：写数据
			.wr_mask_i(m2_data_flow_forwarding.reg_data[1]),          //输入：rj寄存器存放的写掩码
			//for interrupt
			.interrupt_i(int_i),        //输入：中断信号
			//for exception
			.ecode_i(ecode),            //输入：两条流水线的例外一级码
			.esubcode_i(esubcode),         //输入：两条流水线的例外二级码
			.excp_trigger_i(excp_trigger),     //输入：发生异常的流水级
			.bad_va_i(bad_va),           //输入：地址相关例外出错的虚地址
			.instr_pc_i(m2_data_flow_forwarding.pc),         //输入：指令pc
			.do_redirect_o(m2_csr_jump_req),      //输出：是否发生跳转
			.lsu_clr_hint_o(m2_lsu_clr_hint),
			.redirect_addr_o(m2_csr_jump_target),    //输出：返回或跳转的地址
			.m2_clr_exclude_self_o(m2_clr_exclude_self_o),
			//todo：tlb related exceptions
			// timer
			.timer_data_o(timer_data_o),                //输出：定时器值
			.tid_o(tid_o),                        //输出：定时器id
			//todo: llbit
			//todo: tlb related addr translate

			// TLB 连线
			.tlb_entry_i(tlb_entry_i),
			.mmu_resp_i(m2_mmu_resp)

		`ifdef _DIFFTEST_ENABLE
    		,.delay_csr_i(delay_csr_i)
    	`endif
		);

		// Mem 1 部分，准备读取Tag和Data的地址，进行MMU比较。 （转发源）
		// MMU connection here
		logic da_mode,pg_mode,dmw0_en,dmw1_en;
		assign pg_mode = !csr_module.reg_crmd[`_CRMD_DA] && csr_module.reg_crmd[`_CRMD_PG];
		assign da_mode = csr_module.reg_crmd[`_CRMD_DA] && !csr_module.reg_crmd[`_CRMD_PG];
		always_comb begin
			mmu_req_o = '{
				trans_en: pg_mode && !dmw0_en && !dmw1_en, //TODO: CACHEOP && (m1_ctrl_flow.decode_info.m2.cacheop_i)
				vaddr:    m1_saddr,
				dmw0_en:  dmw0_en ,
				dmw1_en:  dmw1_en ,
				default:  '0
			};
		end

		// Exception defines here
		excp_handler excp_handler_module(
			.decode_info_i(m2_ctrl_flow.decode_info),
			.excp_i(m2_excp_flow),
			.vpc_i(m2_data_flow_forwarding.pc),
			.vlsu_i(m2_vaddr),
			.ecode_o(ecode),
			.esubcode_o(esubcode),
			.excp_trigger_o(excp_trigger),
			.bad_va_o(bad_va)
		);
		assign m2_clr_req_o = m2_csr_jump_req & ~stall_vec_i[2];
	end else begin
		assign m2_lsu_read = '0;
		assign m2_csr_read = '0;
		assign m2_clr_req_o = '0;
		assign m2_clr_exclude_self_o = '0;
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

	// 转发信号源生成
	assign forwarding_data_o = {wb_data_flow.result,m2_data_flow_raw.result,m1_data_flow_raw.result};

endmodule : backend_pipeline