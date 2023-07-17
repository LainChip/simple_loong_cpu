`include "cached_lsu_v4.svh"

// 注意，这些函数用于做 bank 选择使用。
// 模块假定处理 bank0 的输入，
// random_num 用于处理 bank conflict 时候的选择
// 返回需要的请求地址 (0 或者 1)
// 可以使用 一个 LUT6 实现逻辑
function logic judge_sel(logic[1:0] a, logic[1:0] v);
  return (!v[0] && v[1]) ||
         (v[0] && v[1] && a[0]);
endfunction

module lsu_dm#(
    parameter int PIPE_MANAGE_NUM = 2,
    parameter int BANK_NUM = `_DBANK_CNT, // This two parameter is FIXED ACTUALLY.
    parameter int WAY_CNT = `_DWAY_CNT,
    parameter int SLEEP_CNT = 4
  )(
    input logic clk,
    input logic rst_n,

    input dram_manager_req_t[PIPE_MANAGE_NUM - 1:0] dm_req_i,
    output dram_manager_resp_t[PIPE_MANAGE_NUM - 1:0] dm_resp_o,
    output dram_manager_snoop_t dm_snoop_i,

    output axi_req_t bus_req_o,
    input axi_resp_t bus_resp_i,

    output logic bus_busy_o
  );

  localparam integer BANK_ID_LEN = $clog2(BANK_NUM);

  logic bus_lock;

  // 数据通路部分，实现分 bank 的 data ram
  // 对于 tag ram，直接复制一份
  logic[BANK_NUM - 1 : 0][WAY_CNT - 1 : 0][3:0] dram_we;
  logic[BANK_NUM - 1 : 0][31:0] dram_wdata;
  logic[BANK_NUM - 1 : 0][`_DIDX_LEN - 3 : BANK_ID_LEN] dram_waddr;
  logic[BANK_NUM - 1 : 0][`_DIDX_LEN - 3 : BANK_ID_LEN] dram_raddr;
  logic[BANK_NUM - 1 : 0][WAY_CNT - 1 : 0][31:0] dram_rdata_d1;
  for(genvar b = 0 ; b < BANK_NUM ; b++) begin
    for(genvar w = 0 ; w < WAY_CNT ; w++) begin
      simpleDualPortRamByteen #(
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

  logic[WAY_CNT - 1 : 0] tram_we,tram_re;
  dcache_tag_t tram_wdata;
  logic[7:0] tram_waddr;
  logic[BANK_NUM - 1 : 0][7:0] tram_raddr;
  dcache_tag_t [BANK_NUM - 1 : 0][WAY_CNT - 1 : 0] tram_rdata_d1;
  for(genvar w = 0 ; w < WAY_CNT ; w++) begin
    simpleDualPortRamRE #(
                          .dataWidth($size(dcache_tag_t)),
                          .ramSize(1 << 8),
                          .readMuler(1),
                          .latency(1)
                        ) tag_ram_p0 (
                          .clk,
                          .rst_n,
                          .addressA(tram_waddr),
                          .we(tram_we[w]),
                          .addressB(tram_raddr[0]),
                          .re(tram_re[w]),
                          .inData(tram_wdata),
                          .outData(tram_rdata_d1[0][w])
                        );
    simpleDualPortRamRE #(
                          .dataWidth($size(dcache_tag_t)),
                          .ramSize(1 << 8),
                          .readMuler(1),
                          .latency(1)
                        ) tag_ram_p1 (
                          .clk,
                          .rst_n,
                          .addressA(tram_waddr),
                          .we(tram_we[w]),
                          .addressB(tram_raddr[1]),
                          .re(tram_re[w]),
                          .inData(tram_wdata),
                          .outData(tram_rdata_d1[1][w])
                        );
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
  logic[1:0] dr_req_valid,dr_req_valid_q;
  logic[1:0] dr_req_ready_q; // 返回值使用
  logic[1:0] dr_req_sel_q;
  logic[1:0][`_DIDX_LEN - 3 : 0] dr_req_addr;
  logic[1:0][`_DIDX_LEN - 3 : BANK_ID_LEN] dram_rnormal_other_q,dram_rnormal_other,dram_rnormal,dram_rfsm;

  wire bank0_sel_normal = judge_sel({dr_req_addr[1][0],dr_req_addr[0][0]}, dr_req_valid);
  wire bank1_sel_normal = judge_sel({dr_req_addr[0][0],dr_req_addr[1][0]}, dr_req_valid);
  wire bank0_sel_other = judge_sel({dr_req_addr[1][0],dr_req_addr[0][0]}, dr_req_valid);
  wire bank1_sel_other = judge_sel({dr_req_addr[0][0],dr_req_addr[1][0]}, dr_req_valid);

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
    end
    if(dreq_fsm_q == DREQ_FSM_PREEMPTION) begin
      dr_req_ready_q <= '0;
    end
    if(dreq_fsm_q == DREQ_FSM_CONFLICT) begin
      dr_req_ready_q <= {dr_req_ready_q[0],dr_req_ready_q[1]};
    end
  end

  // 对读请求的响应
  always_comb begin
    dm_resp_o[0].rdata_d1 = dram_rdata_d1[dr_req_sel_q[0]];
    dm_resp_o[1].rdata_d1 = dram_rdata_d1[dr_req_sel_q[1]];
    dm_resp_o[0].r_valid_d1 = dr_req_valid_q[0];
    dm_resp_o[1].r_valid_d1 = dr_req_valid_q[1];
    dm_resp_o[0].tag_d1 = tram_rdata_d1[0];
    dm_resp_o[1].tag_d1 = tram_rdata_d1[1];
    if(dreq_fsm_q == DREQ_FSM_CONFLICT) begin
      tram_re = '0;
    end
    else begin
      tram_re = '1;
    end
  end

  // ram 的请求
  always_comb begin
    tram_raddr[0] = tramaddr(dm_req_i[0].raddr);
    tram_raddr[1] = tramaddr(dm_req_i[1].raddr);
    dr_req_addr[0] = dramaddr(dm_req_i[0].raddr);
    dr_req_addr[1] = dramaddr(dm_req_i[1].raddr);
    dr_req_valid[0] = dm_req_i[0].rvalid; // TODO: 处理冲突
    dr_req_valid[1] = dm_req_i[1].rvalid;
  end

  // dirty ram
  logic[1:0][7:0] dirty_raddr;
  logic[7:0] dirty_waddr;
  logic[WAY_CNT - 1 : 0] dirty_we;
  logic dirty_wdata;
  logic[1:0][WAY_CNT - 1 : 0] dirty_rdata;

  // 重填主状态机
  // 写回仲裁器
  // 注意写回条件（无进行中的 CACHE 操作事务）
  // 注意，每次主状态机完成处理后，等待一段时间（2 ticks），使得 slave 完成相关写入后再进行下一次处理
  logic op_sel_q;
  logic op_valid_q; // TODO: 产生 valid 和 sel 的逻辑，这里是固定优先级方法。即当 槽1 上的 OP valid 时，优先处理 槽1 的。
  // 主状态机完成处理后的休息时间 （2 ticks） 也在这里实现。
  // 等主装态机完成一半的休息时时 （1 ticks），通知从设备op完成响应。
  // 相关参数可以设置为可配置。
  logic[$clog2(WAY_CNT) : 0] refill_sel_q; // 最高位无效，避免 -1:0 的情况。
  logic refill_state_update;
  logic[$clog2(WAY_CNT) : 0] refill_sel_f;
  logic refill_state_force;
  if(WAY_CNT == 1) begin
    assign refill_sel_q = '0;
  end
  else begin
    // TODO: REFILL LOGIC HERE.
    always_ff @(posedge clk) begin
      if(refill_state_force) begin
        refill_sel_q[$clog2(WAY_CNT) - 1: 0] <= refill_sel_f[$clog2(WAY_CNT) - 1: 0];
      end
      else begin
        if(refill_state_update)
          refill_sel_q[$clog2(WAY_CNT) - 1: 0] <= refill_sel_q[$clog2(WAY_CNT) - 1: 0] + 1;
      end
      refill_sel_q[$clog2(WAY_CNT)] <= '0;
    end
  end
  logic sleep_cnt_rst;
  logic sleep_end_q; // TODO: FINISH THIS SIGNAL.
  logic sleep_end_half_q;
  if(SLEEP_CNT != 0) begin
    logic[$clog2(SLEEP_CNT)-1: 0] sleep_cnt_q;
    always_ff @(posedge clk) begin
      if(~rst_n || sleep_cnt_rst) begin
        sleep_end_q <= 1'b0;
        sleep_end_half_q <= 1'b0;
        sleep_cnt_q <= '0;
      end
      else begin
        if(sleep_cnt_q[$clog2(SLEEP_CNT)-2 : 0] == '1) begin
          if(sleep_cnt_q[$clog2(SLEEP_CNT)-1]) begin
            sleep_end_q <= 1'b1;
          end
          else begin
            sleep_end_half_q <= 1'b1;
          end
        end
        else begin
          sleep_cnt_q <= sleep_cnt_q + 1;
        end
      end
    end
  end
  else begin
    assign sleep_end_q = '0;
  end
  // TODO: 接上这几个信号（需要进行调度）
  logic[3:0] op_q;
  logic[31:0] op_addr_q;
  localparam logic[3:0] MAIN_C_REFILL     = 4'd1;
  localparam logic[3:0] MAIN_C_UNCREAD    = 4'd2;
  localparam logic[3:0] MAIN_C_INVALID    = 4'd4;
  localparam logic[3:0] MAIN_C_INVALID_WB = 4'd8;
  logic op_ready;   // 注意，此状态机还需要考虑，对于重填请求，从设备是不需要答复响应的。
  typedef logic[5:0] main_fsm_t;
  main_fsm_t main_fsm_q,main_fsm;
  localparam main_fsm_t MAIN_FSM_NORMAL = 0;
  localparam main_fsm_t MAIN_FSM_WAIT_BUS = 1;
  localparam main_fsm_t MAIN_FSM_REFIL_RADR = 2;
  localparam main_fsm_t MAIN_FSM_REFIL_RDAT = 3;
  localparam main_fsm_t MAIN_FSM_REFIL_WADR = 4;
  localparam main_fsm_t MAIN_FSM_REFIL_WDAT = 5;
  localparam main_fsm_t MAIN_FSM_PRADR      = 6;
  localparam main_fsm_t MAIN_FSM_PRDAT      = 7;
  localparam main_fsm_t MAIN_FSM_INVALIDATE  = 8;
  always_ff@(posedge clk) begin
    if(!rst_n) begin
      main_fsm_q <= MAIN_FSM_NORMAL;
    end
    else begin
      main_fsm_q <= main_fsm;
    end
  end
  always_comb begin
    main_fsm = main_fsm_q;
    case(main_fsm_q)
      MAIN_FSM_NORMAL: begin
        if(op_valid_q && sleep_end_q) begin
          if(op_q == MAIN_C_REFILL && dirty_rdata[op_sel_q][refill_sel_q]) begin
            if(bus_lock) begin
              main_fsm = MAIN_FSM_WAIT_BUS;
            end
            else begin
              main_fsm = MAIN_FSM_REFIL_WADR;
            end
          end
          else if(op_q == MAIN_C_REFILL) begin
            if(bus_lock) begin
              main_fsm = MAIN_FSM_WAIT_BUS;
            end
            else begin
              main_fsm = MAIN_FSM_REFIL_RADR;
            end
          end
          else if(op_q == MAIN_C_UNCREAD) begin
            if(bus_lock) begin
              main_fsm = MAIN_FSM_WAIT_BUS;
            end
            else begin
              main_fsm = MAIN_FSM_PRADR;
            end
          end
          else if((op_q & (MAIN_C_INVALID_WB | MAIN_C_INVALID)) != 0) begin
            main_fsm = MAIN_FSM_INVALIDATE;
          end
        end
      end
      MAIN_FSM_WAIT_BUS: begin
        if(!bus_lock) begin
          main_fsm = MAIN_FSM_NORMAL;
        end
      end
      MAIN_FSM_REFIL_RADR: begin
        if(bus_resp_i.ready) begin
          main_fsm = MAIN_FSM_REFIL_RDAT;
        end
      end
      MAIN_FSM_REFIL_RDAT: begin
        if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
          main_fsm = MAIN_FSM_NORMAL;
        end
      end
      MAIN_FSM_REFIL_WADR: begin
        if(bus_resp_i.ready) begin
          main_fsm = MAIN_FSM_REFIL_WDAT;
        end
      end
      MAIN_FSM_REFIL_WDAT: begin
        if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
          if(op_q == MAIN_C_REFILL) begin
            main_fsm = MAIN_FSM_REFIL_RADR;
          end
          else begin
            main_fsm = MAIN_FSM_NORMAL;
          end
        end
      end
      MAIN_FSM_PRADR: begin
        if(bus_resp_i.ready) begin
          main_fsm = MAIN_FSM_PRDAT;
        end
      end
      MAIN_FSM_PRDAT: begin
        if(bus_resp_i.data_ok & bus_resp_i.data_last) begin
          main_fsm = MAIN_FSM_NORMAL;
        end
      end
      MAIN_FSM_INVALIDATE: begin
        if(op_q == MAIN_C_INVALID_WB && dirty_rdata[op_sel_q][refill_sel_q]) begin
          main_fsm = MAIN_FSM_REFIL_WADR;
        end
        else begin
          main_fsm = MAIN_FSM_NORMAL;
        end
      end
    endcase
  end

  // CACHE 写回状态机
  // 这个状态机需要对两个不同的请求进行写回的操作。
  // 可以观察到，当两个不同的请求出现 BANK CONFLICT 时，一个周期内无法完成。
  // 考虑到，既然我们目前需要在 M2 级进行 FMT，那么对于写请求，实际上并没有必要在 M1 级别取出其值。
  // 这样实现，对于冲突的两条写请求，仅需要暂停一个周期，更为合理。
  // 在路径延迟方面是一致的，且无法降低 （实际上我感觉也没有必要降低，不会很高）

  // CACHE 总线交互机制
  always_comb begin
    // TODO:根据 FSM 状态及总线状态及时的赋值
  end

  // CACHE 写机制
  logic[1:0] dram_wreq_valid;
  logic[1:0] dram_wreq_ready; // 仅负责 CACHE 的写
  // 对于 UNCACHED 的写，使用另一套状态机维护
  // CACHE 的写，只在主状态机为 NORMAL 下允许进行。
  typedef logic[2:0] cacw_fsm_t;
  cacw_fsm_t cacw_fsm_q,cacw_fsm;
  localparam cacw_fsm_t CAC_FSM_NORMAL = 1;
  localparam cacw_fsm_t CAC_FSM_WBANKCONFLICT = 2; // MAY BE BANK CONFLICTED
  localparam cacw_fsm_t CAC_FSM_DIRTYCONFLICT = 4; // MAY BE NOT BANK CONFLICTED
  always_ff @(posedge clk) begin
    if(~rst_n) begin
      cacw_fsm_q <= CAC_FSM_NORMAL;
    end
    else begin
      cacw_fsm_q <= cacw_fsm;
    end
  end
  always_comb begin
    cacw_fsm = cacw_fsm_q;
    case(cacw_fsm_q)
      CAC_FSM_NORMAL: begin
        if(dram_wreq_valid[0] && dram_wreq_valid[1] && dm_req_i[0].op_addr[2] == dm_req_i[1].op_addr[2]) begin
          cacw_fsm |= CAC_FSM_WBANKCONFLICT; // 此时先响应 req 0 再响应 req 1
        end
        if((((~dirty_rdata[0]) & dm_req_i[0].we_sel) != 0 && dram_wreq_valid[0]) ||
            (((~dirty_rdata[1]) & dm_req_i[1].we_sel) != 0 && dram_wreq_valid[1])) begin
          cacw_fsm |= CAC_FSM_DIRTYCONFLICT;
        end
      end
      default: begin
        cacw_fsm = CAC_FSM_NORMAL;
      end
    endcase
  end

  logic[1:0] uncac_wreq_valid;
  logic[1:0] uncac_wreq_ready; // TODO: 为其赋值
  logic uncac_fifo_full;

  always_comb begin
    // uncac_wreq_ready alogorithm here
    // 注意： 这里可能会发生失序。
    // 不过失序并不会造成影响，发生失序的情况，一定是两个写地址访问了不同的地址行。
    if(cacw_fsm == CAC_FSM_NORMAL) begin
      uncac_wreq_ready[0] = uncac_wreq_valid[0];
      uncac_wreq_ready[1] = (~uncac_wreq_valid[0]) & uncac_wreq_valid[1];
    end
    else begin
      uncac_wreq_ready[1] = 1'b1;
    end
  end

  // 一周期最多响应一条
  typedef logic[2:0] uncacw_fsm_t;
  uncacw_fsm_t uncacw_fsm_q,uncacw_fsm;
  localparam uncacw_fsm_t UNCAC_FSM_NORMAL = 1;
  localparam uncacw_fsm_t UNCAC_FSM_SECOND = 2;
  localparam uncacw_fsm_t UNCAC_FSM_FULL = 4; // 允许的请求少于两条时
  always_ff @(posedge clk) begin
    if(~rst_n) begin
      uncacw_fsm_q <= UNCAC_FSM_NORMAL;
    end
    else begin
      uncacw_fsm_q <= uncacw_fsm;
    end
  end
  always_comb begin
    uncacw_fsm = uncacw_fsm_q;
    case(uncacw_fsm_q)
      UNCAC_FSM_NORMAL: begin
        if((|uncac_wreq_valid) && uncac_fifo_full) begin
          uncacw_fsm = UNCAC_FSM_FULL;
        end
        else if(&uncac_wreq_valid) begin
          uncacw_fsm = UNCAC_FSM_SECOND;
        end
      end
      UNCAC_FSM_SECOND: begin
        uncacw_fsm = UNCAC_FSM_NORMAL;
      end
      UNCAC_FSM_FULL: begin
        if(!uncac_fifo_full) begin
          uncacw_fsm = UNCAC_FSM_NORMAL;
        end
      end
    endcase
  end

  // 将来自 pipeline manager 的写请求合适的接入此 data manager 上
  always_comb begin
    for(integer i = 0 ; i < 2 ; i ++) begin
      uncac_wreq_valid[i] = dm_req_i[i].we_valid && dm_req_i[i].uncached;
      dram_wreq_valid[i] = dm_req_i[i].we_valid && !dm_req_i[i].uncached;
    end
  end

  logic bank0_wsel;
  logic bank1_wsel;

  // TODO: DRAM 写赋值
  always_comb begin
    dram_waddr = main_fsm_q == MAIN_FSM_NORMAL ? (cacw_fsm_q == CAC_FSM_NORMAL ? dramaddr(dm_req_i[0].op_addr)
               : dramaddr(dm_req_i[1].op_addr)) :
               dramaddr (op_addr_q); // TODO: 重填地址相关逻辑在此
    if(main_fsm_q == MAIN_FSM_NORMAL) begin
      dram_wdata = '1;
      dram_we = '0;
    end
    else begin
      dram_we = '0;
    end
  end

  // TODO: TAG 写赋值
  always_comb begin
    if(main_fsm_q == MAIN_FSM_NORMAL) begin
      tram_wdata = '0;
      tram_waddr = '0;
      tram_we = '0;
    end
  end

  // TODO: DIRTY 写赋值
  always_comb begin
    if(main_fsm_q == MAIN_FSM_NORMAL) begin
      dirty_wdata = '1;
      if(cacw_fsm_q == CAC_FSM_NORMAL) begin
        dirty_waddr = tramaddr(dm_req_i[0].op_addr);
        dirty_we = dm_req_i[0].we_valid ? dm_req_i[0].we_sel : '0;
      end else begin
        dirty_waddr = tramaddr(dm_req_i[1].op_addr);
        dirty_we = dm_req_i[1].we_valid ? dm_req_i[1].we_sel : '0;
      end
    end else begin
      // 对于重填写 / invalidate 的 cache 行，需要对应无效化其 dirty 位
      dirty_wdata = '0;
      dirty_waddr = tramaddr(op_addr_q);
      dirty_we = (main_fsm_q &(MAIN_FSM_REFIL_WDAT | MAIN_FSM_INVALIDATE)) != 0 ?  refill_sel_q : '0;
    end
  end

endmodule
