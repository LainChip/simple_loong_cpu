`include "pipeline.svh"
`include "../lsu/lsu_types.svh"

function fwd_data_t mkfwddata(pipeline_wdata_t in);
  mkfwddata.valid = in.w_flow.valid;
  mkfwddata.id = in.w_flow.w_id;
  mkfwddata.data = in.w_data;
endfunction

module backend(
    input logic clk,
    input logic rst_n,

    input frontend_req_t frontend_req_i,
    output frontend_resp_t frontend_resp_o,

    input cache_bus_resp_t bus_resp_i,
    output cache_bus_req_t bus_req_o
  );

  /* -- -- -- -- -- GLOBAL CONTROLLING LOGIC BEGIN -- -- -- -- -- */
  // TODO: PIPELINE ME
  pipeline_ctrl_ex_t[1:0] pipeline_ctrl_is,pipeline_ctrl_skid_q,
                    pipeline_ctrl_ex,pipeline_ctrl_ex_q;
  pipeline_ctrl_m1_t[1:0] pipeline_ctrl_m1,pipeline_ctrl_m1_q;
  pipeline_ctrl_m2_t[1:0] pipeline_ctrl_m2,pipeline_ctrl_m2_q;
  pipeline_ctrl_wb_t[1:0] pipeline_ctrl_wb,pipeline_ctrl_wb_q;

  pipeline_data_t [1:0] pipeline_data_is,pipeline_data_is_fwd,
                  pipeline_data_skid_q,pipeline_data_skid_fwd,
                  pipeline_data_ex_q,pipeline_data_ex_fwd,
                  pipeline_data_m1_q,pipeline_data_m1_fwd,
                  pipeline_data_m2_q,pipeline_data_m2_fwd,
                  pipeline_data_wb_q;
  // TODO: PIPELINE ME
  pipeline_wdata_t [1:0] pipeline_wdata_ex,pipeline_wdata_m1_q,
                   pipeline_wdata_m1,pipeline_wdata_m2_q,
                   pipeline_wdata_m2,pipeline_wdata_wb_q,
                   pipeline_wdata_wb;

  fwd_data_t [1:0] fwd_data_ex,fwd_data_m1,fwd_data_m2,fwd_data_wb;

  // TODO: PIPELINE ME
  exc_flow_t [1:0] exc_is,exc_ex_q,exc_m1_q,exc_m2_q,exc_wb_q;

  logic ex_stall;
  logic m1_stall;
  logic m2_stall;
  logic wb_stall;

  logic[1:0] ex_stall_req;
  logic[1:0] m1_stall_req;
  logic[1:0] m2_stall_req;
  logic[1:0] wb_stall_req;

  // 注意： invalidate 不同于 ~rst_n ，只要求无效化指令，不清除管线中的指令。
  logic [1:0]m1_invalidate, m1_invalidate_req;
  logic ex_invalidate;

  logic is_skid_q;

  // STALL MANAGER
  // 后续级可以阻塞前级
  // 就算前级中有气泡，也不可以前进（并没有必要，徒增stall逻辑复杂度）。但前级不能阻塞后级。
  always_comb begin
    ex_stall = |ex_stall_req | |m1_stall_req | |m2_stall_req | |wb_stall_req;
    m1_stall = |m1_stall_req | |m2_stall_req | |wb_stall_req;
    m2_stall = |m2_stall_req | |wb_stall_req;
    wb_stall = |wb_stall_req;
  end

  // INVALIDATE MANAGER
  always_comb begin
    ex_invalidate = |m1_invalidate_req;
    m1_invalidate[0] = m1_invalidate_req[0];
    m1_invalidate[1] = m1_invalidate_req[0] | m1_invalidate_req[1];
  end

  // forwarding manager
  /* 所有级流水的前递模块在这里实例化*/
  for(genvar p = 0 ; p < 2 ; p++) begin
    dyn_fwd_unit #(2) is_fwd(
                   {fwd_data_wb, fwd_data_ex},
                   pipeline_data_is[p],
                   pipeline_data_is_fwd[p]
                 );
    dyn_fwd_unit #(2) is_skid_fwd(
                   {fwd_data_wb, fwd_data_ex},
                   pipeline_data_skid_q[p],
                   pipeline_data_skid_fwd[p]
                 );
    dyn_fwd_unit #(3) ex_fwd(
                   {fwd_data_wb, fwd_data_m2, fwd_data_m1},
                   pipeline_data_ex_q[p],
                   pipeline_data_ex_fwd[p]
                 );
    always_ff@(posedge clk) begin
      if(ex_stall) begin
        pipeline_data_ex_q[p] <= pipeline_data_ex_fwd[p];
      end
      else begin
        pipeline_data_ex_q[p] <= is_skid_q ? pipeline_data_skid_fwd[p]: pipeline_data_is_fwd[p];
      end
    end
    dyn_fwd_unit #(2) m1_fwd(
                   {fwd_data_wb, fwd_data_m2},
                   pipeline_data_m1_q[p],
                   pipeline_data_m1_fwd[p]
                 );
    always_ff@(posedge clk) begin
      if(m1_stall) begin
        pipeline_data_m1_q[p] <= pipeline_data_m1_fwd[p];
      end
      else begin
        pipeline_data_m1_q[p] <= pipeline_data_ex_fwd[p];
      end
    end
    dyn_fwd_unit #(1) m2_fwd(
                   {fwd_data_wb},
                   pipeline_data_m2_q[p],
                   pipeline_data_m2_fwd[p]
                 );
    always_ff@(posedge clk) begin
      if(m1_stall) begin
        pipeline_data_m2_q[p] <= pipeline_data_m2_fwd[p];
      end
      else begin
        pipeline_data_m2_q[p] <= pipeline_data_m1_fwd[p];
      end
    end
  end

  // LSU 端口实例化


  // MUL 端口实例化
  logic[1:0] mul_req;
  logic[1:0][1:0] mul_op_req;
  logic[1:0][31:0] mul_r0_req,mul_r1_req;
  logic[1:0] mul_op;
  logic[31:0] mul_r0,mul_r1,mul_result;
  always_comb begin
    mul_op = mul_req[0] ? mul_op_req[0] : mul_op_req[1];
    mul_r0 = mul_req[0] ? mul_r0_req[0] : mul_r0_req[1];
    mul_r1 = mul_req[0] ? mul_r1_req[0] : mul_r1_req[1];
  end
  muler_32x32 mul_i(
                .clk(clk),
                .rst_n(rst_n),
                .op_i(mul_op),

                .ex_stall_i(ex_stall),
                .m1_stall_i(m1_stall),
                .m2_stall_i(m2_stall),

                .r0_i(mul_r0),
                .r1_i(mul_r1),

                .result_o(mul_result)
              );

  /* -- -- -- -- -- GLOBAL CONTROLLING LOGIC BEGIN -- -- -- -- -- */

  /* ------ ------ ------ ------ ------ IS 级 ------ ------ ------ ------ ------ */
  // ISSUE 级别：
  // 判定来自前段的指令能否发射
  logic is_ready;
  logic ex_skid_ready_q,ex_skid_valid;
  logic [1:0] issue;
  issue issue_inst (
          .clk(clk),
          .rst_n(rst_n),
          .inst_i(frontend_req_i.inst),
          .d_valid_i(frontend_req_i.inst_valid & {is_ready,is_ready}),
          .ex_ready_i(ex_skid_ready_q),
          .ex_valid_o(ex_skid_valid),
          .is_o(issue)
        );
  assign frontend_resp_o.issue = issue;

  // 读取寄存器堆，或者生成立即数
  logic[1:0][1:0][4:0] is_r_addr;
  logic[1:0][1:0][31:0] is_r_data;
  logic[1:0][1:0] is_r_ready;
  logic[1:0][1:0][3:0] is_r_id;
  logic[1:0][4:0] is_w_addr;
  logic[2:0] is_w_id;

  logic[1:0][4:0] wb_w_addr;
  logic[1:0][31:0] wb_w_data;
  logic[2:0] wb_w_id;
  logic[1:0] wb_valid;
  logic[1:0] wb_commit;
  reg_file # (
             .DATA_WIDTH(32)
           )
           reg_file_inst (
             .clk(clk),
             .rst_n(rst_n),
             .r_addr_i(is_r_addr),
             .r_data_o(is_r_data),
             .w_addr_i(wb_w_addr),
             .w_data_i(wb_w_data),
             .w_en_i(wb_valid & wb_commit)
           );

  // 读取 scoreboard，判断寄存器值是否有效
  scoreboard  scoreboard_inst (
                .clk(clk),
                .rst_n(rst_n),
                .invalidate_i(),
                .issue_ready_o(is_ready),
                .is_r_addr_i(is_r_addr),
                .is_r_id_o(is_r_id),
                .is_r_valid_o(is_r_ready),
                .is_w_addr_i(is_w_addr),
                .is_i(issue),
                .is_w_id_o(is_w_id),
                .wb_w_addr_i(wb_w_addr),
                .wb_w_id_i(wb_w_id),
                .wb_valid_i(wb_valid)
              );

  // 产生 EX 级的流水线信号 x 2
  logic ex_ready, ex_valid;
  // IS 数据前递部分（EX、WB），输入是 pipeline_ctrl_is ，输出 pipeline_ctrl_is_fwd 不完全。

  /* SKID BUF */
  // SKID 数据前递部分（EX、WB） 不完全。
  // 输入是 pipeline_ctrl_skid_q，输出 pipeline_ctrl_skid_fwd
  // SKID BUF 对于 scoreboard 来说应该是透明的，使用 valid-ready 握手
  // assign ex_skid_ready_q = ~is_skid_q;
  always_ff @(posedge clk) begin
    if(~rst_n || ex_invalidate) begin
      is_skid_q <= '0;
      ex_skid_ready_q <= '1;
    end
    else begin
      if(is_skid_q) begin
        if(ex_ready) begin
          is_skid_q <= '0;
          ex_skid_ready_q <= '1;
        end
        pipeline_data_skid_q <= pipeline_data_skid_fwd;
      end
      else begin
        if(ex_skid_valid & ~ex_ready) begin
          is_skid_q <= '1;
          ex_skid_ready_q <= '0;
        end
        pipeline_data_skid_q <= pipeline_data_is_fwd;
      end
    end
  end
  /* SKID BUF 结束*/
  /* ------ ------ ------ ------ ------ EX 级 ------ ------ ------ ------ ------ */
  for(genvar p = 0 ; p < 2 ; p++) begin
    // EX 级别
    // EX 的 FU 部分，接入 ALU、乘法器、除法队列 pusher（Optional）
    logic[31:0] alu_result;
    logic[31:0] jump_target;
    logic[31:0] vaddr, rel_target;
    detachable_alu #(
          .USE_LI(1),
          .USE_INT(0),
          .USE_SFT(0),
          .USE_CMP(0)
        )ex_alu(
          .grand_op_i(pipeline_ctrl_ex_q[p].decode_info.alu_grand_op),
          .op_i(pipeline_ctrl_ex_q[p].decode_info.alu_op),

          .r0_i(pipeline_data_ex_q[p].r_data[0]),
          .r1_i(pipeline_data_ex_q[p].r_data[1]),
          .pc_i(pipeline_ctrl_ex_q[p].pc),

          .res_o(alu_result)
        );

    excp_flow_t ex_excp_flow;
    // ex_excp_flow 产生逻辑
    always_comb begin

    end

    // EX 的额外部分
    // EX 级别的访存地址计算 / 地址翻译逻辑
    always_comb begin
      vaddr = {{6{pipeline_ctrl_ex_q[p].addr_imm[25]}},
               pipeline_ctrl_ex_q[p].addr_imm} +
            pipeline_data_ex_q[p].r_data[1];
    end
    always_comb begin
      rel_target = pipeline_ctrl_ex_q[p].pc + {{6{pipeline_ctrl_ex_q[p].addr_imm[25]}},
                 pipeline_ctrl_ex_q[p].addr_imm};
    end
    always_comb begin
      // TODO
      jump_target = pipeline_ctrl_ex_q[p].target_type == `_TARGET_ABS ?
                  vaddr : rel_target;
    end

    // EX 的结果选择部分
    always_comb begin
      pipeline_wdata_ex[p].w_data = alu_result;
      pipeline_wdata_ex[p].w_flow.w_id = pipeline_ctrl_ex_q[p].w_id; // TODO: FIXME
      pipeline_wdata_ex[p].w_flow.w_addr = pipeline_ctrl_ex_q[p].w_reg;
      pipeline_wdata_ex[p].w_flow.w_valid =
                       pipeline_ctrl_ex_q[p].fu_sel_ex == `_FUSEL_EX_ALU ? (
                         (&pipeline_data_ex_q[p].r_flow.r_ready)) :
                       '0;
    end

    // 接入转发源
    always_comb begin
      fwd_data_ex[p] = mkfwddata(pipeline_wdata_ex[p]);
    end

    // 接入暂停请求
    always_comb begin
      ex_stall_req[p] = ((pipeline_ctrl_ex_q[p].latest_r0_ex & ~pipeline_data_ex_q[p].r_flow.r_ready[0]) |
                         (pipeline_ctrl_ex_q[p].latest_r0_ex & ~pipeline_data_ex_q[p].r_flow.r_ready[0]) ) &
                  exc_ex_q.valid_inst & exc_ex_q.need_commit; // LUT6 - 1
    end

    // 接入 dcache
    /* TODO */

    // 接入 mul
    always_comb begin
      mul_req[p] = pipeline_ctrl_ex_q[p].decode_info.need_mul;
      mul_op_req[p] = pipeline_ctrl_ex_q[p].decode_info.alu_op;
      mul_r0_req[p] = pipeline_data_ex_q[p].r_data[0];
      mul_r1_req[p] = pipeline_data_ex_q[p].r_data[1];
    end

    // 流水线间信息传递
    always_comb begin
      pipeline_ctrl_m1[p].decode_info = get_m1_from_ex(pipeline_ctrl_ex_q[p].decode_info);
      pipeline_ctrl_m1[p].bpu_predict = pipeline_ctrl_ex_q[p].bpu_predict;
      pipeline_ctrl_m1[p].excp_flow = ex_excp_flow;
      pipeline_ctrl_m1[p].csr_id = pipeline_ctrl_ex_q[p].addr_imm[13:0];
      pipeline_ctrl_m1[p].jump_target = jump_target;
      pipeline_ctrl_m1[p].vaddr = vaddr;
      pipeline_ctrl_m1[p].pc = pipeline_ctrl_ex_q[p].pc;
    end
  end

  /* ------ ------ ------ ------ ------ M1 级 ------ ------ ------ ------ ------ */
  // M1 数据接受前递部分（M2、WB） 完全

  // M1 的 FU 部分，接入 ALU、LSU（EARLY）

  // M1 的额外部分
  // CSR读写地址的输入 / 跳转及异常的处理 ， BARRIER 指令的执行（DBAR、 IBAR）。

  /* ------ ------ ------ ------ ------ M2 级 ------ ------ ------ ------ ------ */
  // M2 数据接受前递部分（WB）完全

  // M2 的 FU 部分，接入 ALU、LSU、MUL、CSR

  // M2 的额外部分
  // CSR 修改相关指令的执行，如写 CSR、写 TLB、缓存控制均在此处执行。

  /* ------ ------ ------ ------ ------ WB 级 ------ ------ ------ ------ ------ */
  // 不存在数据前递

  // WB 的 FU 部分，接入 DIV，等待 DIV 完成。

  // WB 需要接回 IS 级的 寄存器堆和 scoreboard

endmodule

