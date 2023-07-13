// 全新设计思路，分离流水线部分以及管理部分
// 流水线部分只负责和管线部分交互，完全不在乎 RAM 管理部分如何对 RAM 进行维护和管理。
// 流水线部分高度可配置，支持组相连 / 直接映射。
// CACHE 的管理部分不支持 byte-wide operation， CACHE 需要手动控制写操作进行融合。

`define _DWAY_CNT 1
`define _DIDX_LEN 12
`define _DTAG_LEN 20
`define _DCAHE_OP_READ 1
`define _DCAHE_OP_WRITE 2

typedef struct packed {
          logic rvalid;
          logic[31:0] raddr;

          logic we_valid;
          logic wuncached;
          logic[`_DWAY_CNT - 1 : 0] we_sel;
          logic[31:0] waddr;
          logic[31:0] wdata;

          logic op_valid;
          logic[3:0]  op_type;
          logic[31:0] op_addr;
        } dram_manager_req_t;

typedef struct packed {
          logic valid;
          logic[`_DTAG_LEN - 1 : 0] addr;
        } dcache_tag_t;

typedef struct packed {
          logic pending_write; // means that rdata_d1 is not the most newest value now.

          dcache_tag_t[`_DWAY_CNT - 1 : 0] tag_d0;
          dcache_tag_t[`_DWAY_CNT - 1 : 0] tag_d1;
          // dcache_tag_t etag_d0; // TODO
          // dcache_tag_t etag_d1;

          logic[`_DWAY_CNT - 1 : 0][31:0] rdata_d1;
          logic rdata_valid_d1;

          logic we_ready;

          logic op_ready;
        } dram_manager_resp_t;

// 有 256 个 CACHE 行
typedef struct packed {
          logic [`_DWAY_CNT - 1 : 0] tag_we;
          logic [7:0] tag_waddr;
          dcache_tag_t tag_wdata;

          logic [`_DWAY_CNT - 1 : 2] data_we;
          logic [`_DIDX_LEN - 1 : 2] data_waddr;
          logic [31:0] data_wdata;
        } dram_manager_snoop_t;

function logic[`_DTAG_LEN - 1 : 0] tagaddr(logic[31:0] va);
  return va[`_DTAG_LEN + `_DIDX_LEN - 1: `_DIDX_LEN];
endfunction
function logic[7 : 0] tramaddr(logic[31:0] va);
  return va[`_DIDX_LEN - 1 -: 8];
endfunction
function logic[`_DIDX_LEN - 1 : 2] dramaddr(logic[31:0] va);
  return va[`_DIDX_LEN - 1 : 2];
endfunction
function logic cache_hit(dcache_tag_t tag,logic[31:0] pa);
  return tag.valid && (tagaddr(pa) == tag.addr);
endfunction
function logic[31:0] mkstrobe(logic[31:0] data, logic[3:0] mask);
  return data & {{8{mask[3]}},{8{mask[2]}},{8{mask[1]}},{8{mask[0]}}};
endfunction

module lsu #(
    parameter int WAY_CNT = 1
  ) (
    input logic clk,
    input logic rst_n,

    input logic [31:0] ex_vaddr_i,
    input logic ex_valid_i,
    input logic [31:0] m1_vaddr_i,
    input logic [31:0] m1_paddr_i,
    input logic [31:0] m1_wdata_i,
    input logic [ 3:0] m1_strobe_i, // 读写复用
    input logic m1_valid_i,
    input logic m1_uncached_i,
    output logic m1_busy_o, // M1 级的 LSU 允许 stall
    input logic m1_stall_i,

    output logic [31:0] m1_rdata_o,
    output logic m1_rvalid_o,  // 结果早出级

    input logic [31:0] m2_vaddr_i,
    input logic [31:0] m2_paddr_i,
    input logic [ 3:0] m2_strobe_i, // 读写复用
    input logic m2_valid_i,
    input logic m2_uncached_i,
    input logic [1:0] m2_size_i, // uncached 专用
    output logic m2_busy_o, // M2 级别的 LSU 允许 stall
    input logic m2_stall_i,
    input logic [2:0] m2_op_i,

    output logic [31:0] m2_rdata_o,
    output logic m2_rvalid_o,  // 需要 fmt 的结果级

    output logic [31:0] wb_rdata_o,
    output logic wb_rvalid_o,


    output dram_manager_req_t dm_req_o,
    input dram_manager_resp_t dm_resp_i,
    input dram_manager_snoop_t dm_snoop_i
  );
  // EX 级接线（真的就是单纯的接线）
  always_comb begin
    dm_req_o.rvalid = ex_valid_i;
    dm_req_o.raddr = ex_vaddr_i;
  end

  // M1 级接线，具有时序逻辑。
  // M1 级共三个状态：
  // NORMAL，即为正常状态，可以接受请求
  // WAIT，即为等待 dram_manager 状态，等待 rdata_valid_d1 置高，且依然需要监视 snoop 端口
  // SNOOP，读端口上的数据已经就绪，等待 cpu 管线撤回 stall 信号，持续监视 snoop 端口

  // M1 状态机电路
  logic[2:0] m1_fsm_q, m1_fsm;
  localparam logic[2:0]M1_FSM_NORMAL = 3'b001;
  localparam logic[2:0]M1_FSM_WAIT = 3'b010;
  localparam logic[2:0]M1_FSM_SNOOP = 3'b100;
  always_ff@(posedge clk) begin
    if(~rst_n) begin
      m1_fsm_q <= M1_FSM_NORMAL;
    end
    else begin
      m1_fsm_q <= m1_fsm;
    end
  end
  always_comb begin
    m1_fsm = m1_fsm_q;
    casez(m1_fsm_q)
      3'b??1: begin
        if(m1_valid_i && !dm_resp_i.rdata_valid_d1) begin
          m1_fsm = M1_FSM_WAIT;
        end
        else if(m1_stall_i) begin
          m1_fsm = M1_FSM_SNOOP;
        end
      end
      3'b?10: begin
        if(dm_resp_i.rdata_valid_d1) begin
          if(!m1_stall_i) begin
            m1_fsm = M1_FSM_NORMAL;
          end
          else begin
            m1_fsm = M1_FSM_SNOOP;
          end
        end
      end
      3'b100: begin
        if(!m1_stall_i) begin
          m1_fsm = M1_FSM_NORMAL;
        end
      end
      default: begin
        // 非合法值
        m1_fsm = M1_FSM_NORMAL;
      end
    endcase
  end

  // M1 嗅探电路
  logic[WAY_CNT - 1 : 0][31:0] m1_data_q,m1_data;
  dcache_tag_t[WAY_CNT - 1 : 0] m1_tag_q,m1_tag;
  always_ff @(posedge clk) begin
    m1_data_q <= m1_data;
    m1_tag_q <= m1_tag;
  end
  always_comb begin
    m1_data = ((m1_fsm_q & (M1_FSM_NORMAL | M1_FSM_WAIT)) != 0) ? dm_resp_i.rdata_d1 : m1_data_q;
    for(integer i = 0 ; i < WAY_CNT ; i++) begin
      if(dm_snoop_i.data_we[i] && dm_snoop_i.data_waddr == dramaddr(m1_vaddr_i)) begin
        m1_data[i] = dm_snoop_i.data_wdata;
      end
    end
  end
  always_comb begin
    m1_tag = ((m1_fsm_q & (M1_FSM_NORMAL | M1_FSM_WAIT)) != 0) ? dm_resp_i.tag_d1 : m1_tag_q;
    for(integer i = 0 ; i < WAY_CNT ; i++) begin
      if(dm_snoop_i.tag_we[i] && dm_snoop_i.tag_waddr == tramaddr(m1_vaddr_i)) begin
        m1_tag[i] = dm_snoop_i.tag_wdata;
      end
    end
  end

  // M1 output 电路
  if(WAY_CNT == 1) begin
    always_comb begin
      // 早出条件较为苛刻，要求之前没有未完成的写请求，缓存命中，非不可缓存。
      m1_rdata_o = mkstrobe(dm_resp_i.rdata_d1[0], m1_strobe_i);
      m1_rvalid_o = dm_resp_i.rdata_valid_d1 && cache_hit(dm_resp_i.tag_d1[0], m1_paddr_i)
                  && !dm_resp_i.pending_write && !m1_uncached_i
                  && (m1_paddr_i[1:0] == '0);
    end
  end
  else begin
    always_comb begin
      m1_rdata_o = '0;
      m1_rvalid_o = '0;
    end
  end

  // M1 busy 电路
  always_comb begin
    m1_busy_o = (m1_fsm_q != M1_FSM_NORMAL) || (m1_fsm_q == M1_FSM_NORMAL && m1_valid_i && !dm_resp_i.rdata_valid_d1);
  end

  // 注意：这部分需要在 M1 - M2 级之间进行流水。
  logic [WAY_CNT - 1 : 0] m1_hit,m2_hit_q,m2_hit;
  logic m1_miss,m2_miss_q,m2_miss;

  // M1 HIT MISS 电路
  for(genvar i = 0 ; i < WAY_CNT ; i++) begin
    assign m1_hit[i] = cache_hit(m1_tag, m1_paddr_i);
  end
  assign m1_miss = ~|m1_hit;

  // M2 控制流水线寄存器
  always_ff @(posedge clk) begin
    m2_hit_q  <= m2_hit;
    m2_miss_q <= m1_miss;
  end

  // M2 MISS / HIT 维护
  always_comb begin
    // 时刻监控对 tag 的读写，以维护新的 hit / miss
    m2_hit = m2_hit_q;
    for(integer i = 0 ; i < WAY_CNT ; i++) begin
      if(dm_snoop_i.tag_we[i] && dm_snoop_i.tag_waddr == tramaddr(m2_vaddr_i)) begin
        m2_hit = cache_hit(dm_snoop_i.tag_wdata, m2_paddr_i);
      end
    end
    m2_miss = ~|m2_hit;
  end

  // M2 状态机
  // 这个状态机需要做得事情很有限，所有 CACHE 操作请求都通过 request 的形式提交给 RAM 管理者进行，
  // 本地只需要轮询本地寄存器等待结果被从 snoop 中捕捉到就可以了。
  logic[6:0] m2_fsm_q,m2_fsm;
  localparam logic[6:0] M2_FSM_NORMAL      = 7'b0000001;
  localparam logic[6:0] M2_FSM_CREAD_MISS  = 7'b0000010;
  localparam logic[6:0] M2_FSM_UREAD_WAIT  = 7'b0000100;
  localparam logic[6:0] M2_FSM_CWRITE_MISS = 7'b0001000;
  localparam logic[6:0] M2_FSM_UWRITE_WAIT = 7'b0010000;
  localparam logic[6:0] M2_FSM_CACHE_OP    = 7'b0100000;
  localparam logic[6:0] M2_FSM_WAIT_STALL  = 7'b1000000;
  always_ff@(posedge clk) begin
    if(!rst_n) begin
      m2_fsm_q <= M2_FSM_NORMAL;
    end
    else begin
      m2_fsm_q <= m2_fsm;
    end
  end
  always_comb begin
    m2_fsm = m2_fsm_q;
    case (m2_fsm_q)
      M2_FSM_NORMAL: begin
        if(m2_valid_i && !m2_uncached_i && m2_miss_q) begin
          if(m2_op_i == `_DCAHE_OP_READ) begin
            m2_fsm = M2_FSM_CREAD_MISS;
          end else if(m2_op_i == `_DCAHE_OP_WRITE) begin
            m2_fsm = M2_FSM_CWRITE_MISS;
          end
        end
        else if(m2_valid_i && m2_uncached_i) begin
          if(m2_op_i == `_DCAHE_OP_READ) begin
            m2_fsm = M2_FSM_UREAD_WAIT;
          end else if(m2_op_i == `_DCAHE_OP_WRITE && !dm_resp_i.we_ready) begin
            m2_fsm = M2_FSM_UWRITE_WAIT;
          end
        end
        else if(m2_valid_i && m2_op_i != '0) begin
          m2_fsm = M2_FSM_CACHE_OP;
        end
      end
      M2_FSM_CREAD_MISS: begin
        
      end
      M2_FSM_CWRITE_MISS: begin
        
      end
      default:
      endcase
  end
endmodule
