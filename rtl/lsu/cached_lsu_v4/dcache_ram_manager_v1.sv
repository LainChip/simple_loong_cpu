`include "cached_lsu_v4.svh"

// 注意，这些函数用于做 bank 选择使用。
// 模块假定处理 bank0 的输入，
// random_num 用于处理 bank conflict 时候的选择
// 返回需要的请求地址 (0 或者 1)
// 可以使用 一个 LUT6 实现逻辑
function logic judge_sel(logic[1:0] a, logic[1:0] v, logic r);
  return (!v[0] && v[1]) ||
         (v[0] && v[1] && !a[0] && !a[1] && r) ||
         (v[0] && v[1] && a[0]);
endfunction

module lsu_dm#(
    parameter int PIPE_MANAGE_NUM = 2,
    parameter int BANK_NUM = `_DBANK_CNT, // This two parameter is FIXED ACTUALLY.
    parameter int WAY_CNT = `_DWAY_CNT
  )(
    input logic clk,
    input logic rst_n,

    input dram_manager_req_t[PIPE_MANAGE_NUM - 1:0] dm_req_o,
    output dram_manager_resp_t[PIPE_MANAGE_NUM - 1:0] dm_resp_i,
    output dram_manager_snoop_t dm_snoop_i,

    output axi_req_t bus_req_o,
    input axi_resp_t bus_resp_i
  );

  localparam integer BANK_ID_LEN = $clog2(BANK_NUM);

  // 数据通路部分，实现分 bank 的 data ram 和 tag ram
  logic[BANK_NUM - 1 : 0][WAY_CNT - 1 : 0] dram_we;
  logic[BANK_NUM - 1 : 0][31:0] dram_wdata;
  logic[BANK_NUM - 1 : 0][`_DIDX_LEN - 3 : BANK_ID_LEN] dram_waddr;
  logic[BANK_NUM - 1 : 0][`_DIDX_LEN - 3 : BANK_ID_LEN] dram_raddr;
  logic[BANK_NUM - 1 : 0][WAY_CNT - 1 : 0][31:0] dram_rdata_d1;
  for(genvar b = 0 ; b < BANK_NUM ; b++) begin
    for(genvar w = 0 ; w < WAY_CNT ; w++) begin
      simpleDualPortRam #(
                          .dataWidth(32),
                          .ramSize(1 << (`_DIDX_LEN - 2 - BANK_ID_LEN)),
                          .readMuler(1),
                          .latency(1)
                        ) data_ram (
                          .clk,
                          .rst_n,
                          .addressA(dram_waddr[b]),
                          .we(dram_we[b][w]),
                          .addressB(dram_raddr[b]),
                          .inData(dram_wdata[b]),
                          .outData(dram_rdata_d1[b][w])
                        );
    end
  end

  logic[BANK_NUM - 1 : 0][WAY_CNT - 1 : 0] tram_we;
  dcache_tag_t [BANK_NUM - 1 : 0] tram_wdata;
  logic[BANK_NUM - 1 : 0][7:BANK_ID_LEN] tram_waddr;
  logic[BANK_NUM - 1 : 0][7:BANK_ID_LEN] tram_raddr;
  dcache_tag_t [BANK_NUM - 1 : 0][WAY_CNT - 1 : 0] tram_rdata_d1;
  for(genvar b = 0 ; b < BANK_NUM ; b++) begin
    for(genvar w = 0 ; w < WAY_CNT ; w++) begin
      simpleDualPortRam #(
                          .dataWidth($size(dcache_tag_t)),
                          .ramSize(1 << (8 - BANK_ID_LEN)),
                          .readMuler(1),
                          .latency(1)
                        ) tag_ram (
                          .clk,
                          .rst_n,
                          .addressA(tram_waddr[b]),
                          .we(tram_we[b][w]),
                          .addressB(tram_raddr[b]),
                          .inData(tram_wdata[b]),
                          .outData(tram_rdata_d1[b][w])
                        );
    end
  end

  // 数据请求处理状态机，响应 dm_req 中的数据管理部分
  // 具体来说，根据 rvalid / raddr 信号对请求进行处理。
  // 对于没有 bank conflict 的情况，正常输出即可。
  // 对于 bank conflict 的情况，等待一拍处理第二个请求即可。
  // 即每一个 banked ram 读地址输入为一个四选一逻辑。
  // 特别的，存在一种情况，这种情况，两个请求均不可响应，响应高优先级请求（重填写回）。
  logic dreq_conflict;
  logic dram_preemption_valid;
  logic dram_preemption_ready;
  logic[`_DIDX_LEN - 3 : 0] dram_preemption_addr;

  // 状态控制
  logic[3:0] dreq_fsm_q,dreq_fsm;
  parameter DREQ_FSM_NORMAL = 4'b0001;
  parameter DREQ_FSM_CONFLICT = 4'b0010;
  parameter DREQ_FSM_PREEMPTION = 4'b0100;
  always_ff @(posedge clk) begin
    if(~rst_n) begin
      dreq_fsm_q <= DREQ_FSM_NORMAL;
    end
    else begin
      dreq_fsm_q <= dreq_fsm;
    end
  end
  always_comb begin
    dreq_fsm = dreq_fsm_q;
    case(dreq_fsm_q)
      DREQ_FSM_NORMAL: begin
        if(dram_preemption_valid) begin
          dreq_fsm = DREQ_FSM_PREEMPTION;
        end
        else if(dreq_conflict) begin
          dreq_fsm = DREQ_FSM_CONFLICT;
        end
      end
      DREQ_FSM_CONFLICT: begin
        dreq_fsm = DREQ_FSM_NORMAL;
      end
      DREQ_FSM_PREEMPTION: begin
        if(!dreq_conflict) begin
          dreq_fsm = DREQ_FSM_NORMAL;
        end
      end
    endcase
  end

  // 输入地址控制
  logic conflict_sel_tick, conflict_sel_tick_n;
  logic[1:0] dr_req_valid,dr_req_valid_q; // TODO: 为其赋值
  logic[1:0] dr_req_ready_q; // 返回值使用
  logic[1:0] dr_req_sel_q;
  logic[1:0][`_DIDX_LEN - 3 : 0] dr_req_addr;// TODO: 为其赋值
  logic[1:0][`_DIDX_LEN - 3 : BANK_ID_LEN] dram_rnormal_other_q,dram_rnormal_other,dram_rnormal,dram_rfsm; // TODO: 为dram_rfsm赋值
  always_ff @(posedge clk) begin
    if(~rst_n) begin
      conflict_sel_tick <= 1'b0;
      conflict_sel_tick_n <= 1'b1;
    end
    conflict_sel_tick <= conflict_sel_tick_n;
    conflict_sel_tick_n <= conflict_sel_tick;
  end
  wire bank0_sel_normal = judge_sel({dr_req_addr[1][0],dr_req_addr[0][0]}, dr_req_valid, conflict_sel_tick);
  wire bank1_sel_normal = judge_sel({dr_req_addr[0][0],dr_req_addr[1][0]}, dr_req_valid, conflict_sel_tick);
  wire bank0_sel_other = judge_sel({dr_req_addr[1][0],dr_req_addr[0][0]}, dr_req_valid, conflict_sel_tick_n);
  wire bank1_sel_other = judge_sel({dr_req_addr[0][0],dr_req_addr[1][0]}, dr_req_valid, conflict_sel_tick_n);

  assign dram_rnormal[0] = bank0_sel_normal ? dr_req_addr[1][`_DIDX_LEN - 3 : BANK_ID_LEN] : dr_req_addr[0][`_DIDX_LEN - 3 : BANK_ID_LEN];
  assign dram_rnormal[1] = bank1_sel_normal ? dr_req_addr[0][`_DIDX_LEN - 3 : BANK_ID_LEN] : dr_req_addr[1][`_DIDX_LEN - 3 : BANK_ID_LEN];
  assign dram_rnormal_other[0] = bank0_sel_other ? dr_req_addr[1][`_DIDX_LEN - 3 : BANK_ID_LEN] : dr_req_addr[0][`_DIDX_LEN - 3 : BANK_ID_LEN];
  assign dram_rnormal_other[1] = bank1_sel_other ? dr_req_addr[0][`_DIDX_LEN - 3 : BANK_ID_LEN] : dr_req_addr[1][`_DIDX_LEN - 3 : BANK_ID_LEN];

  always_ff @(posedge clk) begin
    dram_rnormal_other_q <= dram_rnormal_other;
  end

  assign dram_raddr = (dreq_fsm == DREQ_FSM_NORMAL) ? dram_rnormal : dram_rfsm;
  assign dram_rfsm = (dreq_fsm_q == DREQ_FSM_CONFLICT) ? dram_rnormal_other_q : dram_preemption_addr[`_DIDX_LEN - 3 : BANK_ID_LEN];

  always_ff @(posedge clk) begin
    if(dreq_fsm_q == DREQ_FSM_NORMAL) begin
        dr_req_sel_q[0] <= dr_req_addr[0][0];
        dr_req_sel_q[1] <= dr_req_addr[1][0];
        dr_req_ready_q[0] <= dr_req_valid[0] && ((!bank0_sel_normal && !dr_req_addr[0][0]) || (bank1_sel_normal && dr_req_addr[0][0]));
        dr_req_ready_q[1] <= dr_req_valid[1] && ((bank0_sel_normal && !dr_req_addr[1][0]) || (!bank1_sel_normal && dr_req_addr[1][0]));
        dr_req_valid_q <= dr_req_valid;
    end else if(dreq_fsm_q == DREQ_FSM_PREEMPTION) begin
        dr_req_ready_q <= '0;
    end else begin
        dr_req_ready_q <= dr_req_ready_q ^ {2{(&dr_req_valid_q) & ~(dr_req_sel_q[0] ^ dr_req_sel_q[1])}};
    end
  end

endmodule
