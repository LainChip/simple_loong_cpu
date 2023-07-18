`include "pipeline.svh"
`include "../lsu/lsu_types.svh"

module backend(
    input logic clk,
    input logic rst_n,

    input frontend_req_t frontend_req_i,
    output frontend_resp_t frontend_resp_o,

    input cache_bus_resp_t bus_resp_i,
    output cache_bus_req_t bus_req_o
  );
  /* ------ ------ ------ ------ ------ IS 级 ------ ------ ------ ------ ------ */
  // ISSUE 级别：
  // 判定来自前段的指令能否发射
  logic ex_skid_ready_q,ex_skid_valid;
  logic ex_ready, ex_valid;
  logic [1:0] issue;
  issue issue_inst (
          .clk(clk),
          .rst_n(rst_n),
          .inst_i(frontend_req_i.inst),
          .d_valid_i(frontend_req_i.inst_valid),
          .ex_ready_i(ex_ready),
          .ex_valid_o(ex_valid),
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
  logic[1:0][2:0] wb_w_id;
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
  // IS 数据前递部分（EX、WB） 不完全。

  /* SKID BUF(可选的) */
  // SKID 数据前递部分（M2、WB） 不完全。
  // SKID BUF 对于 scoreboard 来说应该是透明的，使用 valid-ready 握手
  /* SKID BUF 结束*/
  /* ------ ------ ------ ------ ------ EX 级 ------ ------ ------ ------ ------ */

  logic ex_stall_req, ex_stall;
  logic m1_stall_req, m1_stall;
  logic m2_stall_req, m2_stall;
  logic wb_stall_req, wb_stall;

  // STALL MANAGER
  // 后续级可以阻塞前级就算有气泡，也不可以前进。但前级不能阻塞后级。
  // EX 级别

  // EX 数据前递部分（M1、M2、WB） 完全，需要验证有效性。
  // 输入来自 IS-EX 级别的流水线寄存器。
  // 当 EX 级没有暂停时，EX 的流水线寄存器 来自 IS / SKID BUF
  // 当 EX 级暂停的时候（ex_stall == 1），EX 的流水线寄存器，来自转发后的 EX

  // EX 的 FU 部分，接入 ALU、乘法器、除法队列 pusher（Optional）

  // EX 的额外部分
  // EX 级别的访存地址计算 / 地址翻译逻辑

  // EX 级别的目标地址计算
  // 接入 dcache

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
