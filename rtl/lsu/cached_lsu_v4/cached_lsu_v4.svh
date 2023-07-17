`ifndef _CACHED_LSU_V3_HEADER
`define _CACHED_LSU_V3_HEADER

        // 全新设计思路，分离流水线部分以及管理部分
        // 流水线部分只负责和管线部分交互，完全不在乎 RAM 管理部分如何对 RAM 进行维护和管理。
        // 流水线部分高度可配置，支持组相连 / 直接映射。
        // CACHE 的管理部分不支持 byte-wide operation， CACHE 需要手动控制写操作进行融合。

`define _DWAY_CNT 1
`define _DBANK_CNT 2
`define _DIDX_LEN 12
`define _DTAG_LEN 20
`define _DCAHE_OP_READ 1
`define _DCAHE_OP_WRITE 2

typedef struct packed {
          logic valid;
          logic[`_DTAG_LEN - 1 : 0] addr;
        } dcache_tag_t;

typedef struct packed {
          logic rvalid;
          logic[31:0] raddr;

          logic we_valid;
          logic uncached;
          logic[3:0] strobe;
          logic[1:0] size;
          logic[`_DWAY_CNT - 1 : 0] we_sel;
          logic[31:0] wdata;

          logic op_valid;
          logic[2:0]  op_type;
          logic[31:0] op_addr;
          dcache_tag_t[`_DWAY_CNT - 1 : 0] old_tags;
        } dram_manager_req_t;

typedef struct packed {
          logic pending_write; // means that rdata_d1 is not the most newest value now.

          // dcache_tag_t[`_DWAY_CNT - 1 : 0] tag_d0; // NO USAGE NOW
          dcache_tag_t[`_DWAY_CNT - 1 : 0] tag_d1;
          // dcache_tag_t etag_d0; // TODO
          // dcache_tag_t etag_d1;

          logic[`_DWAY_CNT - 1 : 0][31:0] rdata_d1;
          logic r_valid_d1;

          logic we_ready;
          logic[31:0] r_uncached;

          logic op_ready;
        } dram_manager_resp_t;

// 有 256 个 CACHE 行
typedef struct packed {
          logic [`_DWAY_CNT - 1 : 0] tag_we;
          logic [7:0] tag_waddr;
          dcache_tag_t tag_wdata;

          logic [`_DBANK_CNT - 1 : 0][`_DWAY_CNT - 1 : 0] data_we;
          logic [`_DBANK_CNT - 1 : 0][`_DIDX_LEN - 1 : 2 + $clog2(`_DBANK_CNT)] data_waddr;
          logic [`_DBANK_CNT - 1 : 0][31:0] data_wdata;
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
function logic[`_DIDX_LEN - 1 : 3] bankeddramaddr(logic[31:0] va);
  return va[`_DIDX_LEN - 1 : 3];
endfunction
function logic cache_hit(dcache_tag_t tag,logic[31:0] pa);
  return tag.valid && (tagaddr(pa) == tag.addr);
endfunction
function logic[31:0] mkstrobe(logic[31:0] data, logic[3:0] mask);
  return data & {{8{mask[3]}},{8{mask[2]}},{8{mask[1]}},{8{mask[0]}}};
endfunction
function logic[31:0] mksft(logic[31:0] raw, logic[31:0] va);
  // M1 WDATA 电路
  mksft = raw;
  case(va[1:0])
    default: begin
      mksft = raw;
    end
    2'b01: begin
      mksft[7:0] = raw[15:8];
    end
    2'b10: begin
      mksft[15:0] = raw[31:16];
    end
    2'b11: begin
      mksft[7:0] = raw[31:24];
    end
  endcase

endfunction

typedef struct packed {
          logic ar_valid;
          logic[31:0] ar_addr;
          logic[3:0] ar_len;
          logic ar_uncached;
          logic[2:0] ar_size;
          logic aw_valid;
          logic[31:0] aw_addr;
          logic[3:0] aw_id;
          logic[3:0] aw_len;
          logic aw_uncached;
          logic[2:0] aw_size;
          logic dr_ready;
          logic dw_valid;
          logic dw_last;
          logic[31:0] dw_data;
          logic[3:0] dw_strobe;
          logic b_ready;
        } axi_req_t;

typedef struct packed {
          logic ar_ready;
          logic aw_ready;
          logic dr_valid;
          logic dr_last;
          logic[31:0] dr_data;
          logic dw_ready;
          logic   b_valid;
        } axi_resp_t;


`endif
