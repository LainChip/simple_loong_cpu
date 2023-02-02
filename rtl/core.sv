`include "common.svh"
`include "decoder.svh"
`include "pipeline.svh"
`include "lsu_types.svh"
`include "bpu.svh"
`include "csr.svh"
`include "tlb.svh"

module core(
    input clk,
    input rst_n,
    input [7:0] int_i,
    AXI_BUS.Master mem_bus
);

inst_t 		     [1:0]inst;
logic  		     [1:0]inst_valid;
logic  		     [1:0]issue_num;
logic  		     backend_stall;
bpu_update_t     bpu_feedback;
priv_req_t   	 priv_req;
priv_resp_t      priv_resp;
cache_bus_req_t	 ibus_req , dbus_req;
cache_bus_resp_t ibus_resp, dbus_resp;
mmu_s_resp_t     immu_resp, dmmu_resp;
tlb_entry_t      r_tlbentry;

// axi converter
axi_converter #(.CACHE_PORT_NUM(2))axi_converter(
	.clk(clk),.rst_n(rst_n),
	.axi_bus_if(mem_bus),
	.req_i({dbus_req,ibus_req}),
	.resp_o({dbus_resp,ibus_resp})
);

// frontend
frontend frontend(
	.clk(clk),
	.rst_n(rst_n),

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
    .bus_resp_i(ibus_resp),      // cache的访问应答

	// MMU
	.mmu_resp_i(immu_resp)
);

    // backend
backend backend(
	.clk(clk),
	.rst_n(rst_n),
	.int_i(int_i),

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
    .bus_resp_i(dbus_resp),     // cache的访问应答

	// MMU
	.mmu_resp_i(dmmu_resp),
	.tlb_entry_i(r_tlbentry)
);

// MMU
mmu #(
	.TLB_PORT(2)
) mmu(
	.clk(clk),
	.rst_n(rst_n),
	.stall_i(backend.pipeline_0.stall_vec_i[2]),
	.mmu_s_req_i ({'0/*TODO*/          , backend.mmu_req_o  }),
	.mmu_s_resp_o({immu_resp           , dmmu_resp          }),

	.decode_info_i(backend.pipeline_0.m2_ctrl_flow.decode_info),
	.tlbehi_i     (backend.pipeline_0.sp_inst_blk.csr_module.reg_tlbehi),
	.tlbelo0_i    (backend.pipeline_0.sp_inst_blk.csr_module.reg_tlbelo0),
	.tlbelo1_i    (backend.pipeline_0.sp_inst_blk.csr_module.reg_tlbelo1),
	.tlbidx_i     (backend.pipeline_0.sp_inst_blk.csr_module.reg_tlbidx),
	.ecode_i      (backend.pipeline_0.sp_inst_blk.csr_module.reg_estat[`_ESTAT_ECODE]),

	.tlb_entry_o  (r_tlbentry),

	.timer_rand   (backend.pipeline_0.sp_inst_blk.csr_module.timer_data_o),

	.asid         (backend.pipeline_0.sp_inst_blk.csr_module.reg_asid[`_ASID]),
	.invtlb_asid  (backend.pipeline_0.m2_data_flow_forwarding.reg_data[1][`_ASID]),
	.invtlb_vpn   (backend.pipeline_0.m2_data_flow_forwarding.reg_data[0][`_TLBEHI_VPPN]),
	.csr_dmw0_i   (backend.pipeline_0.sp_inst_blk.csr_module.reg_dmw0),
	.csr_dmw1_i   (backend.pipeline_0.sp_inst_blk.csr_module.reg_dmw1),
	.csr_da_i     (backend.pipeline_0.sp_inst_blk.csr_module.reg_crmd[`_CRMD_DA]),
	.csr_pg_i     (backend.pipeline_0.sp_inst_blk.csr_module.reg_crmd[`_CRMD_PG])
);

`ifdef _DIFFTEST_ENABLE
	assign backend.debug_rand_index = mmu.debug_rand_index;
`endif

endmodule
