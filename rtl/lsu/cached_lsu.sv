`include "common.svh"
`include "decoder.svh"
`include "lsu_types.svh"

/*--JSON--{"module_name":"lsu","module_ver":"2","module_type":"module"}--JSON--*/

// 8.11 double-issue writeback is too complex, i will make it simplier.
// 8.13 i will add uncached write buffer to this cache, lock bus will be attach to write buffer.
// 2.13 change interface to match new cpu request.

`define _CACHE_CTRL_INVALID (4'd0)
`define _CACHE_CTRL_READ (4'd1)
`define _CACHE_CTRL_WRITE (4'd2)
`define _CACHE_INDEX_INVALID (4'd3)
`define _CACHE_INDEX_STORE_TAG (4'd4)
`define _CACHE_HIT_INVALID (4'd5)
`define _CACHE_HIT_WRITEBACK_INVALID (4'd6)

module lsu #(
    parameter int page_shift_len = 12,
    parameter int word_shift_len = 2,
    parameter int bank_shift_len = 1,
    parameter int index_len = 6,
    parameter int set_ass = 2,
    parameter int axi_id = 0,
    // parameter int slot_2_8_byte = 0,

    // parameter int force_passthrogh = 0,
    parameter int force_cached = 0
) (
    input logic clk,
    input logic rst_n,
    // input logic force_passthrogh,

    // input  logic stall_i,
    // output logic busy_o,

    // input dcache_req_t d_req,  -- need some build up --
    // input dcache_w_t w_req,    -- data -- byteen --
    // output dcache_resp_t d_resp,
    // output logic [31:0] slot_2_resp,

    // output tlb_req_t  tlb_req,
    // input  tlb_resp_t tlb_resp,

    // input  axi_resp_t axi_resp,
    // output axi_req_t  axi_req,

    // //input logic [31:0] cp0_tag_lo,
    // output logic [1:0] tlb_err_hint,

    // 新增总线忙碌信号
    input  bus_busy_i,
    output bus_busy_o,

    // 控制信号
	input decode_info_t  decode_info_i, // ex stage
	input logic request_valid_i, // ex stage
	
	// 流水线数据输入输出
	input logic[31:0] vaddr_i, // ex stage
	input logic[31:0] paddr_i, // M1 STAGE
	input logic[31:0] w_data_i,  // M2 STAGE
	output logic[31:0] w_data_o,
	input logic request_clr_m2_i,
	input logic request_clr_m1_i,
	output logic[31:0] r_data_o,

	output logic[31:0] vaddr_o,
	output logic[31:0] paddr_o,

	// 连接内存总线
	output cache_bus_req_t bus_req_o,
	input cache_bus_resp_t bus_resp_i,
  input mmu_s_resp_t mmu_resp_i,

	// 握手信号
	output logic busy_o,
	input stall_i

);
  // REQUEST WARPPER
  typedef struct packed {
    logic [31:0] vaddr;
    logic [3:0]  ctrl;   //for now
    logic [1:0]  size;
    logic valid;
  } dcache_req_t;
  typedef struct packed {
    logic [31:0] data;
    logic [3:0]  byteen;
  } dcache_w_t;
  dcache_req_t d_req;
  dcache_w_t   w_req;
  // d_req 赋值逻辑
  always_comb begin
    d_req.vaddr = vaddr_i;
    d_req.ctrl = `_CACHE_CTRL_INVALID;
    d_req.valid = decode_info_i.m1.mem_valid & request_valid_i;
    if(decode_info_i.m1.mem_valid) begin
      // read or write
      if(decode_info_i.m1.mem_write) begin
        d_req.ctrl = `_CACHE_CTRL_WRITE;
      end else begin
        d_req.ctrl = `_CACHE_CTRL_READ;
      end
    end
    if(decode_info_i.m2.cacop && decode_info_i.general.inst25_0[2:0] == 3'd1) begin
      if(decode_info_i.general.inst25_0[4:3] == 2'b00) begin
        // store tag
        d_req.ctrl = `_CACHE_INDEX_STORE_TAG;
      end else if(decode_info_i.general.inst25_0[4:3] == 2'b01) begin
        // index invalidate
        d_req.ctrl = `_CACHE_INDEX_INVALID;
      end else begin
        // hit invalidate
        d_req.ctrl = `_CACHE_HIT_WRITEBACK_INVALID;
      end
    end
    case(decode_info_i.m1.mem_type[1:0])
			`_MEM_TYPE_WORD: begin
				d_req.size = 2'b10;
			end
			`_MEM_TYPE_HALF: begin
				d_req.size = 2'b01;
			end
			`_MEM_TYPE_BYTE: begin
				d_req.size = 2'b00;
			end
			default: begin
				d_req.size = 2'b00;
			end
    endcase
  end
  logic[2:0] delay_1_req_type,delay_2_req_type;
  always_ff @(posedge clk) begin
    if(~stall_i) begin
      delay_1_req_type <= decode_info_i.m1.mem_type[2:0];
      delay_2_req_type <= delay_1_req_type;
    end
  end
	// w_req 赋值逻辑
	always_comb begin
    w_req.data = w_data_i << {paddr_o[1:0],3'b000};
		case(delay_2_req_type[1:0])
			`_MEM_TYPE_WORD: begin
				w_req.byteen = 4'b1111;
			end
			`_MEM_TYPE_HALF: begin
				w_req.byteen = (4'b0011 << {paddr_o[1],1'b0});;
			end
			`_MEM_TYPE_BYTE: begin
				w_req.byteen = (4'b0001 << paddr_o[1:0]);
			end
			default: begin
				w_req.byteen = 4'b0000;
			end
		endcase
	end

  // stall logic
  logic stall_pipe;
  assign stall_pipe = busy_o | stall_i;
  logic delay_stall;
  logic delay_stall_outside;
  logic bus_busy;
  assign bus_busy = bus_busy_i  /*& bus_busy_o*/;

  always_ff @(posedge clk) begin : proc_delay_stall
    delay_stall <= stall_pipe;
  end
  always_ff @(posedge clk) begin
    delay_stall_outside <= stall_i & ~busy_o;
  end

  localparam int lane_len = page_shift_len - word_shift_len - index_len;
  localparam int lane_size = 1 << lane_len;
  localparam int word_size_in_byte = 1 << word_shift_len;
  localparam int word_size_in_bits = 8 * word_size_in_byte;
  localparam int page_no_len = 32 - page_shift_len;
  localparam int lane_num = 1 << index_len;
  typedef logic [page_no_len - 1 : 0] ppn_t;
  typedef logic [set_ass - 2 : 0] lru_t;
  typedef struct packed {
    ppn_t ppn;
    logic valid;
    logic dirty;
  } cache_lane_info_t;

  // Here we describe a big register file about cache controlling infomation.
  // All cache info updation should be complete in final stage, after miss/hit processing.

  cache_lane_info_t stage_2_write_info;
  logic stage_2_write_info_enable;
  logic [index_len - 1 : 0] stage_2_waddr;
  logic [$clog2(set_ass) - 1 : 0] stage_2_set_sel;

  //logic data_conflict;  // Should never happend
  logic [3:0] data_req_w_enable;
  logic [(1 << word_shift_len) * 8 - 1 : 0] data_req_w_data;
  logic [$clog2(set_ass) - 1 : 0] data_req_w_set_sel;
  logic [page_shift_len - word_shift_len - 1 : 0] data_req_w_addr;
  logic [page_shift_len - word_shift_len - 1 : 0] data_req_r_addr;
  logic [page_shift_len - word_shift_len - 1 : 0] fsm_data_req_r_addr;
  logic [1:0][set_ass - 1 : 0][word_size_in_bits - 1 : 0] data_resp_r_data;

  data_cache_datapath_opt #(
      .set_ass       (set_ass),
      .word_shift_len(2),
      .index_len     (6),
      .page_shift_len(12),
      .bank_shift_len(1)
  ) data_path (
      .clk(clk),
      .rst_n(rst_n),
      .req_r_addr({
        data_req_r_addr[page_shift_len-word_shift_len-1 : 1],
        {(1'b1 ^ data_req_r_addr[0])},
        data_req_r_addr[page_shift_len-word_shift_len-1 : 1],
        {(1'b0 ^ data_req_r_addr[0])}
      }),
      .valid(2'b11),
      .req_w_enable(data_req_w_enable),
      .req_w_data(data_req_w_data),
      .resp_r_data(data_resp_r_data),
      .req_w_set_sel(data_req_w_set_sel),
      .req_w_addr(data_req_w_addr)
  );

  // Build up the Normal path
  logic [page_shift_len - word_shift_len - 1 : 0] normal_data_req_r_addr;
  assign normal_data_req_r_addr = d_req.vaddr[page_shift_len-1:word_shift_len];
  // Additional data register
  logic [1:0][set_ass - 1 : 0][word_size_in_bits - 1 : 0] delay_normal_data_resp_r_data;
  logic [1:0][set_ass - 1 : 0][word_size_in_bits - 1 : 0] normal_data_resp_r_data;
  logic [$clog2(set_ass) - 1 : 0] stage_2_next_lru_sel;
  logic [$clog2(set_ass) - 1 : 0] stage_2_hit_index;

  always_ff @(posedge clk) begin : proc_delay_normal_data_resp_r_data
    if (~delay_stall_outside) delay_normal_data_resp_r_data <= data_resp_r_data;
  end
  assign normal_data_resp_r_data = delay_stall_outside ? delay_normal_data_resp_r_data : data_resp_r_data;

  // This block connect cache to tlb
  // assign tlb_req.vaddr = d_req.vaddr;

  // This block describe a switch to switch data_path controller between fsm and normal stage.
  // When stall, the controll is given to fsm.
  assign data_req_r_addr = stall_pipe ? fsm_data_req_r_addr : normal_data_req_r_addr;

  // We need request information , so that we can do some refilling and selecting work load.
  // Request type and va[31:word_shift_len] is needed.
  typedef struct packed {
    logic [31:0] vaddr; // BUG: THIS IS ACTUALLY PADDR IN STAGE 2
    logic [31:0] paddr;
    logic [3:0] ctrl;  //for now
    logic [1:0] size;
    logic passthrough;
  } dcache_req_append_t;
  dcache_req_append_t delay_1_req;
  (* mark_debug = "true" *)dcache_req_append_t delay_2_req;
  always_ff @(posedge clk) begin : proc_delay_req
    if (~rst_n || request_clr_m1_i || request_clr_m2_i) begin
      delay_1_req.ctrl <= '0;
      delay_2_req.ctrl <= '0;
    end else if (~stall_pipe) begin
      delay_1_req.vaddr <= d_req.vaddr;
      delay_1_req.ctrl <= d_req.valid ? d_req.ctrl : 0;
      delay_1_req.size <= d_req.size;
      {delay_2_req.vaddr,delay_2_req.ctrl,delay_2_req.size} <= 
      {delay_1_req.vaddr,delay_1_req.ctrl,delay_1_req.size};
      delay_2_req.paddr <= paddr_i;
      delay_2_req.passthrough <= ~mmu_resp_i.mat[0];
    end
  end

  // Build up stage 1 information
  // We need to grab information about hit / miss / dirty , so we need to access information registers.
  typedef struct packed {cache_lane_info_t [set_ass - 1 : 0] cache_lane_info;} cache_info_t;
  cache_info_t stage_1_info;
  cache_info_t stage_1_info_forward;
  cache_info_t stage_2_info;
  // cache_info_t fsm_info;
  logic [index_len - 1 : 0] info_r_addr;
  logic [index_len - 1 : 0] lru_r_addr;

  assign info_r_addr = stall_pipe ? delay_1_req.vaddr[page_shift_len - 1 : page_shift_len - index_len] :
																		    d_req.vaddr[page_shift_len - 1 : page_shift_len - index_len];
  assign lru_r_addr = stall_pipe ? delay_2_req.paddr[page_shift_len - 1 : page_shift_len - index_len] :
																		    delay_1_req.vaddr[page_shift_len - 1 : page_shift_len - index_len];

  // cache_info_t [lane_num - 1 : 0] cache_info;
  // always_ff @(posedge clk) begin : proc_cache_info
  //   if (~rst_n) begin
  //     cache_info <= 0;
  //   end else begin
  //     if (stage_2_write_info_enable)
  //       cache_info[stage_2_waddr].cache_lane_info[stage_2_set_sel] <= stage_2_write_info;
  //   end
  // end
  // always_ff @(posedge clk) begin : proc_normal_info_read
  //   stage_1_info <= cache_info[info_r_addr];
  // end

  //Bram cache info
  cache_lane_info_t cache_info_w_data;
  logic [set_ass - 1 : 0] cache_info_w_enable;
  always_comb begin
    cache_info_w_enable = 0;
    cache_info_w_data = stage_2_write_info;
    for (int i = 0; i < set_ass; i += 1) begin
      cache_info_w_enable[i] = stage_2_write_info_enable && (i == stage_2_set_sel);
    end
  end
  generate
    for (genvar way_id = 0; way_id < set_ass; way_id += 1) begin
      simpleDualPortRam #(
          .dataWidth($size(cache_lane_info_t)),
          .ramSize(lane_num),
          .latency(1),  // Cut down the latency.
          .readMuler(1)
      ) bram_core (
          .clk     (clk),
          .rst_n   (rst_n),
          .addressA(stage_2_waddr),
          .we      (cache_info_w_enable[way_id]),
          .addressB(info_r_addr),
          .inData  (cache_info_w_data),
          .outData (stage_1_info.cache_lane_info[way_id])
      );
    end
  endgenerate

  always_comb begin
    stage_1_info_forward = stage_1_info;
    if(stage_2_write_info_enable && stage_2_waddr == delay_1_req.vaddr[page_shift_len - 1 : page_shift_len - index_len]) begin
      stage_1_info_forward.cache_lane_info[stage_2_set_sel] = stage_2_write_info;
    end
  end

  // Generate hit / miss information in stage 1
  typedef struct packed {
    logic [set_ass - 1 : 0] hit;
    logic miss;
  } hit_miss_info_t;
  hit_miss_info_t stage_1_hit_miss;
  generate
    for (genvar set_id = 0; set_id < set_ass; set_id += 1) begin
      assign stage_1_hit_miss.hit[set_id] = stage_1_info.cache_lane_info[set_id].valid && (stage_1_info.cache_lane_info[set_id].ppn == paddr_i[31:page_shift_len]);
    end
  endgenerate
  //assign stage_1_hit_miss.miss = ~(|stage_1_hit_miss.hit);
  always_comb begin
    if (~mmu_resp_i.mat[0]) begin
      stage_1_hit_miss.miss = 1;
    end else if(delay_1_req.ctrl == `_CACHE_CTRL_READ || delay_1_req.ctrl == `_CACHE_CTRL_WRITE) begin
      stage_1_hit_miss.miss = ~(|stage_1_hit_miss.hit);
    end else if (delay_1_req.ctrl == `_CACHE_CTRL_INVALID) begin
      stage_1_hit_miss.miss = 0;
    end else if(delay_1_req.ctrl == `_CACHE_HIT_INVALID || delay_1_req.ctrl == `_CACHE_HIT_WRITEBACK_INVALID) begin
      stage_1_hit_miss.miss = |stage_1_hit_miss.hit;
    end else begin
      stage_1_hit_miss.miss = 1;
    end
  end

  // The fsm hit miss is maintain by fsm machine in stage 2,
  // Actually, stage 2 is just a huge fsm machine that deal with all command including read/writing.
  // When no miss / special-cache controll command is taken, the fsm machine just working normaly and only need to set up dirty flag in cache info.
  // So we will describe fsm machine here.
  localparam int S_NORMAL = 0;
  localparam int S_UPDATE = 1;
//   localparam int S_AW = 2;
  localparam int S_WADR = 2;
//   localparam int S_DW = 3;
  localparam int S_WDAT = 3;
//   localparam int S_B = 4;
//   localparam int S_AR = 5;
  localparam int S_RADR = 4;
//   localparam int S_DR = 6;
  localparam int S_RDAT = 5;
  localparam int S_SYNC = 6;
  localparam int S_WAIT_LOCK = 7;  // Wait lock before read.
  localparam int S_WAIT_FULL = 8;
//   localparam int S_PAR = 11;

// for read through
  localparam int S_PADR = 9;
//   localparam int S_PDR = 12;
  localparam int S_PDAT = 10;
  //localparam int S_PAW = 13;
  //localparam int S_PDW = 14;
  //localparam int S_PB = 15;
  // In total 14 status, so we need 4 bits to record fsm status.
  logic [3:0] fsm_state;
  logic [3:0] fsm_state_next;
  // logic [1:0][$clog2(set_ass) - 1 : 0] stage_2_next_lru_sel;
  logic [set_ass - 2 : 0] stage_2_lru_info;
  logic [set_ass - 2 : 0] stage_2_lru_update;
  logic [index_len - 1 : 0] stage_2_index_addr;

  // Generate hit / miss information gonne to be used in stage 2:
  hit_miss_info_t stage_2_hit_miss;
  hit_miss_info_t fsm_hit_miss;

  // First, we will define data_type that we gonne used.
  typedef struct packed {
    logic [31:0] req_addr;    // Used in axi-aw
    logic [31:0] req_data;    // Used in axi-dw
    logic [3:0]  req_strobe;  // Used in axi-dw
    logic [2:0]  req_size;    // Used in axi-aw
  } uncached_write_req_t;
  // The signal needed for communication is as folow
  logic uncached_fsm_machine_busy;  // Used to stall when cached-miss, uncached-read.
  logic uncached_fsm_machine_full;  // Used to stall when uncached-write
  // axi_req_t uncached_axi_req;  // When busy, set axi controll to uncached_req, else normal.
  cache_bus_req_t uncached_bus_req_o;
  uncached_write_req_t uncached_req;
  logic uncached_req_valid;
  assign bus_busy_o = uncached_fsm_machine_busy | busy_o;

  always_ff @(posedge clk) begin
    if (~stall_pipe) begin
      stage_2_hit_miss <= stage_1_hit_miss;
    end else begin
      if (fsm_state == S_SYNC) stage_2_hit_miss <= fsm_hit_miss;
    end
  end

  tree_lru_new #(
      .set_size(set_ass)
  ) new_selector (
      .info(stage_2_lru_info),
      .o_index(stage_2_next_lru_sel)
  );
  always_ff @(posedge clk) begin : proc_stage_2_info
    if (~stall_pipe) begin
      stage_2_info <= stage_1_info_forward;
    end else begin
      if (fsm_state == S_SYNC) begin
        stage_2_info.cache_lane_info[stage_2_set_sel] <= stage_2_write_info;
      end
    end
  end
  
  //Generate information we need in stage 2
  lru_t [lane_num - 1 : 0] lru_info;
  always_ff @(posedge clk) begin
    if (~rst_n) stage_2_lru_info <= 0;
    else if (~stall_pipe) stage_2_lru_info <= lru_info[lru_r_addr];
  end  
  always_ff @(posedge clk) begin : proc_lru_info
    if (~rst_n) begin
      lru_info <= 0;
    end else begin
      if (~busy_o) begin
        if ((delay_2_req.ctrl == `_CACHE_CTRL_READ) || (delay_2_req.ctrl == `_CACHE_CTRL_WRITE))
          lru_info[stage_2_index_addr] <= stage_2_lru_update;
      end
    end
  end
// xpm_memory_sdpram
// #(
// 	.ADDR_WIDTH_A($clog2(lane_num)),
// 	.ADDR_WIDTH_B($clog2(lane_num)),
// 	.AUTO_SLEEP_TIME(0),
// 	.BYTE_WRITE_WIDTH_A(set_ass - 1),
// 	.CLOCKING_MODE("common_clock"),
// 	.ECC_MODE("no_ecc"),
// 	.MEMORY_INIT_FILE("none"),
// 	.MEMORY_INIT_PARAM("0"),
// 	.MEMORY_OPTIMIZATION("true"),
// 	.USE_MEM_INIT(0),
// 	.MESSAGE_CONTROL(0),
// 	.MEMORY_PRIMITIVE("distributed"),
// 	.MEMORY_SIZE((set_ass - 1) * lane_num),
// 	.READ_DATA_WIDTH_B(set_ass - 1),
// 	.READ_LATENCY_B(1),
// 	.WRITE_DATA_WIDTH_A(set_ass - 1),
// 	.WRITE_MODE_B("read_first")
// 	)instanceSdpram(
// 	.clka(clk),
// 	.clkb(clk),
// 	.addra(stage_2_index_addr),
// 	.addrb(lru_r_addr),
// 	.rstb(1'b0),
// 	.dina(stage_2_lru_update),
// 	.doutb(stage_2_lru_info),
// 	.wea(~stall_pipe && (delay_2_req.ctrl == `_CACHE_CTRL_READ) || (delay_2_req.ctrl == `_CACHE_CTRL_WRITE)),
// 	.enb(1'b1),
// 	.ena(1'b1),
// 	.sleep(1'b0),
// 	.injectsbiterra(1'b0),
// 	.injectdbiterra(1'b0),
// 	.regceb(~stall_pipe)
// 	);


  always_ff @(posedge clk) begin : proc_fsm_state
    if (~rst_n) begin
      fsm_state <= S_NORMAL;
    end else begin
      fsm_state <= fsm_state_next;
    end
  end

  always_comb begin
    fsm_state_next = fsm_state;
    case (fsm_state)
      S_NORMAL: begin
        if(request_clr_m2_i) begin
            fsm_state_next = fsm_state;
        end else if((delay_2_req.ctrl == `_CACHE_CTRL_READ || delay_2_req.ctrl == `_CACHE_CTRL_WRITE) && ~delay_2_req.passthrough && stage_2_hit_miss.miss) begin
          fsm_state_next = S_UPDATE;
        end else if(delay_2_req.ctrl == `_CACHE_CTRL_READ && delay_2_req.passthrough && stage_2_hit_miss.miss) begin
          // 读透传
          if (bus_busy || uncached_fsm_machine_busy) begin
            fsm_state_next = S_WAIT_LOCK;
          end else begin
            fsm_state_next = S_PADR;
          end
        end else if((delay_2_req.ctrl == `_CACHE_CTRL_WRITE) && delay_2_req.passthrough && stage_2_hit_miss.miss) begin // 写透传
          if (uncached_fsm_machine_full) fsm_state_next = S_WAIT_FULL;
          else fsm_state_next = S_NORMAL;
        end else if((delay_2_req.ctrl == `_CACHE_HIT_WRITEBACK_INVALID || delay_2_req.ctrl == `_CACHE_HIT_INVALID || delay_2_req.ctrl == `_CACHE_INDEX_INVALID || delay_2_req.ctrl == `_CACHE_INDEX_STORE_TAG) && stage_2_hit_miss.miss) begin
          // CACHE指令
          fsm_state_next = S_UPDATE;
        end else begin
          fsm_state_next = S_NORMAL;
        end
      end
      S_WAIT_LOCK: begin
        if (bus_busy || uncached_fsm_machine_busy) begin
          fsm_state_next = S_WAIT_LOCK;
        end else begin
          if (delay_2_req.passthrough) begin
            fsm_state_next = S_PADR;
          end else begin
            fsm_state_next = S_RADR;
          end
        end
      end
      S_UPDATE: begin
        if (delay_2_req.ctrl == `_CACHE_CTRL_READ || delay_2_req.ctrl == `_CACHE_CTRL_WRITE) begin
          // 脏写回
          if(stage_2_info.cache_lane_info[stage_2_next_lru_sel].dirty && stage_2_info.cache_lane_info[stage_2_next_lru_sel].valid) begin
            fsm_state_next = S_WADR;
          end else begin
            if (bus_busy || uncached_fsm_machine_busy) begin
              fsm_state_next = S_WAIT_LOCK;
            end else begin
              fsm_state_next = S_RADR;
            end
          end
        end else begin
          // 控制相关逻辑
          if (delay_2_req.ctrl == `_CACHE_HIT_WRITEBACK_INVALID) begin
            if (stage_2_info.cache_lane_info[stage_2_hit_index].dirty) begin
              fsm_state_next = S_WADR;
            end else begin
              fsm_state_next = S_SYNC;
            end
          end else if (delay_2_req.ctrl == `_CACHE_INDEX_INVALID) begin
            if (stage_2_info.cache_lane_info[delay_2_req.paddr[page_shift_len+$clog2(
                    set_ass
                )-1 : page_shift_len]].dirty &&
                    stage_2_info.cache_lane_info[delay_2_req.paddr[page_shift_len+$clog2(
                    set_ass
                )-1 : page_shift_len]].valid) begin
              fsm_state_next = S_WADR;
            end else begin
              fsm_state_next = S_SYNC;
            end
          end else begin
            fsm_state_next = S_SYNC;
          end
        end
      end
      S_WADR: begin
        if (bus_resp_i.ready && ~uncached_fsm_machine_busy) begin
          fsm_state_next = S_WDAT;
        end else begin
          fsm_state_next = S_WADR;
        end
      end
      S_WDAT: begin
        if (bus_resp_i.data_ok && bus_req_o.data_last) begin
          if (delay_2_req.ctrl == `_CACHE_CTRL_READ || delay_2_req.ctrl == `_CACHE_CTRL_WRITE) begin
            fsm_state_next = S_RADR;
          end else begin
            fsm_state_next = S_SYNC;
          end
        end else begin
          fsm_state_next = S_WDAT;
        end
      end
      // S_B: begin
      //   if (axi_resp.BW_valid) begin
      //     if (delay_2_req.ctrl == `_CACHE_CTRL_READ || delay_2_req.ctrl == `_CACHE_CTRL_WRITE) begin
      //       fsm_state_next = S_AR;
      //     end else begin
      //       fsm_state_next = S_SYNC;
      //     end
      //   end else begin
      //     fsm_state_next = S_B;
      //   end
      // end
      S_RADR: begin
        if (bus_resp_i.ready) begin
          fsm_state_next = S_RDAT;
        end else begin
          fsm_state_next = S_RADR;
        end
      end
      S_PADR: begin
        if (bus_resp_i.ready) begin
          fsm_state_next = S_PDAT;
        end else begin
          fsm_state_next = S_PADR;
        end
      end
      S_RDAT: begin
        if (bus_resp_i.data_ok && bus_resp_i.data_last) begin
          fsm_state_next = S_SYNC;
        end else begin
          fsm_state_next = S_RDAT;
        end
      end
      S_PDAT: begin
        if (bus_resp_i.data_ok && bus_resp_i.data_last) begin
          fsm_state_next = S_SYNC;
        end else begin
          fsm_state_next = S_PDAT;
        end
      end
      S_SYNC: begin
        fsm_state_next = S_NORMAL;
      end
      S_WAIT_FULL: begin
        if (~uncached_fsm_machine_full) begin
          fsm_state_next = S_NORMAL;
        end
      end
      // S_PAW: begin
      //   if (axi_resp.AW_ready) begin
      //     fsm_state_next = S_PDW;
      //   end else begin
      //     fsm_state_next = S_PAW;
      //   end
      // end
      // S_PDW: begin
      //   if (axi_resp.DW_ready && axi_req.DW_last) begin
      //     fsm_state_next = S_PB;
      //   end else begin
      //     fsm_state_next = S_PDW;
      //   end
      // end
      // S_PB: begin
      //   if (axi_resp.BW_valid) begin
      //     fsm_state_next = S_SYNC;
      //   end else begin
      //     fsm_state_next = S_PB;
      //   end
      // end
      default : /* default for reset */
			begin
        fsm_state_next = S_NORMAL;
      end
    endcase
  end

  // Imply fsm operation
  assign stage_2_index_addr = delay_2_req.paddr[page_shift_len-1 : page_shift_len-index_len];

  // 1. Imply cache_info related .
  // Operation controller here, invalidate and update

  // TODO: SIMPLIFY //

  always_comb begin
    stage_2_write_info_enable = '0;
    stage_2_write_info = stage_2_info.cache_lane_info[stage_2_hit_index];
    stage_2_waddr = stage_2_index_addr;
    stage_2_set_sel = stage_2_next_lru_sel;
    if (delay_2_req.ctrl == `_CACHE_INDEX_INVALID || delay_2_req.ctrl == `_CACHE_INDEX_STORE_TAG) begin
      stage_2_set_sel = delay_2_req.paddr[page_shift_len+$clog2(set_ass)-1:page_shift_len];
      stage_2_write_info.dirty = 0;
      stage_2_write_info.valid = 0;
    end else if(delay_2_req.ctrl == `_CACHE_HIT_INVALID || delay_2_req.ctrl == `_CACHE_HIT_WRITEBACK_INVALID) begin
      stage_2_set_sel = stage_2_hit_index;
      stage_2_write_info.dirty = 0;
      stage_2_write_info.valid = 0;
    end else begin
      stage_2_write_info.valid = '1;
      stage_2_write_info.dirty = 0;
      stage_2_write_info.ppn   = delay_2_req.paddr[31:page_shift_len];
    end
    case (fsm_state)
      S_NORMAL: begin
        // 需要及时的更新Dirty
        if (~stall_pipe) begin
          if ((delay_2_req.ctrl == `_CACHE_CTRL_WRITE) && (~delay_2_req.passthrough)) begin
            stage_2_write_info_enable = '1;
            stage_2_set_sel = stage_2_hit_index;
            stage_2_write_info.dirty = 1'b1;
          end
        end
      end
      S_UPDATE: begin
        stage_2_write_info_enable = '1;
      end
      default : /* default */
				begin
        stage_2_write_info_enable = '0;
      end
    endcase
  end

  // 2. Imply busy_o signal 
  assign busy_o = ~((fsm_state == S_NORMAL) && (fsm_state_next == S_NORMAL));

  // 3. Imply lru update signal
  tree_lru_update #(
      .set_size(set_ass)
  ) new_lru_generator (
      .i_update_elm(stage_2_hit_miss.hit),
      .old_info    (stage_2_lru_info),
      .new_info    (stage_2_lru_update)
  );

  // 4. Imply counter and writeback fifo.
  logic w_set_counter;
  logic w_clr_counter;
  logic r_set_counter;
  // Counter controll logic
  always_comb begin
    w_set_counter = 1'b0;
    w_clr_counter = 1'b0;
    r_set_counter = 1'b0;
    case (fsm_state)
      S_NORMAL: begin
        if (fsm_state_next == S_UPDATE) begin
          w_set_counter = 1'b1;
        end else begin
          w_clr_counter = 1'b1;
        end
      end
      S_RADR: begin
        r_set_counter = 1'b1;
        w_clr_counter = 1'b1;
      end
      S_WADR: begin
        r_set_counter = 1'b1;
      end
      default: begin
        w_set_counter = 1'b0;
        r_set_counter = 1'b0;
      end
    endcase
  end

  logic [lane_len : 0] data_transfer_counter;
  logic [lane_len : 0] data_fifo_counter;  // For data fifo, we start from 5'b01111
  logic [lane_len - 1 : 0] addr_counter;  // For data fifo, we start from 5'b01111
  logic [lane_size - 1 : 0][31:0] dirty_data_fifo;
  // dirty writeback fifo logic:
  always_ff @(posedge clk) begin
    if (data_fifo_counter[lane_len]) begin
      if (delay_2_req.ctrl == `_CACHE_HIT_WRITEBACK_INVALID) begin
        dirty_data_fifo[data_fifo_counter[lane_len - 1 : 0]] <= data_resp_r_data[0][stage_2_hit_index];
      end else if (delay_2_req.ctrl == `_CACHE_INDEX_INVALID) begin
        dirty_data_fifo[data_fifo_counter[lane_len - 1 : 0]] <= data_resp_r_data[0][delay_2_req.paddr[page_shift_len + $clog2(
            set_ass)-1 : page_shift_len]];
      end else begin
        dirty_data_fifo[data_fifo_counter[lane_len - 1 : 0]] <= data_resp_r_data[0][stage_2_next_lru_sel];
      end
    end
  end
  always_ff @(posedge clk) begin
    if (~rst_n | w_clr_counter) addr_counter <= '0;
    else if (w_set_counter) addr_counter <= 4'd1;
    else if (|addr_counter) addr_counter <= addr_counter + 1;
  end

  // This block describe fsm_data_req addr switches 
  always_comb begin
    if (busy_o && ((fsm_state == S_NORMAL) || (fsm_state == S_UPDATE) || (fsm_state == S_WADR) || (fsm_state == S_WDAT))) begin
      fsm_data_req_r_addr = {
        delay_2_req.paddr[page_shift_len-1 : word_shift_len+lane_len], addr_counter[lane_len-1 : 0]
      };
    end else begin
      fsm_data_req_r_addr = delay_1_req.vaddr[page_shift_len-1 : word_shift_len];
    end
    if (fsm_state == S_RDAT) begin
      fsm_data_req_r_addr = delay_2_req.paddr[page_shift_len-1 : word_shift_len];
    end
  end
  always_ff @(posedge clk) begin
    if (~rst_n) data_transfer_counter <= '0;
    else if (r_set_counter) data_transfer_counter <= {1'b1, {(lane_len) {1'b0}}};
    else if (data_transfer_counter[lane_len])
      data_transfer_counter <= data_transfer_counter + (((bus_resp_i.data_ok && (fsm_state == S_RDAT)) || (bus_resp_i.data_ok && (fsm_state == S_WDAT))) ? 1 : 0);
  end

  always_ff @(posedge clk) begin
    if (~rst_n) data_fifo_counter <= '0;
    else if (w_set_counter) data_fifo_counter <= {1'b0, {(lane_len) {1'b1}}};
    else if (data_fifo_counter[lane_len] | data_fifo_counter[0])
      data_fifo_counter <= data_fifo_counter + 1;
  end

  // All axi require generate
  always_comb begin
    // Write back allocation:
    // axi_req.DW_data = dirty_data_fifo[data_transfer_counter[lane_len-1 : 0]];
    bus_req_o.w_data = dirty_data_fifo[data_transfer_counter[lane_len-1 : 0]];
    // axi_req.AR_addr = {
    //   delay_2_req.paddr[31:word_shift_len+lane_len], {(word_shift_len + lane_len) {1'b0}}
    // };
    bus_req_o.addr = {
      delay_2_req.paddr[31:word_shift_len+lane_len], {(word_shift_len + lane_len) {1'b0}}
    };
    // axi_req.AR_id = axi_id;
    // axi_req.AR_len = lane_size - 1;
    bus_req_o.burst_size = lane_size - 1;
    // axi_req.AR_cacheType = 4'b0000;
    bus_req_o.cached = '0;
    // axi_req.AR_size = 3'b010;
    bus_req_o.data_size = 2'b10;
    // axi_req.AR_protection = 3'b000;
    // axi_req.AR_burstType = 2'b10;
    // axi_req.AR_lockType = 2'b00;

    // The AW ppn addr is from victim tag, index tag is the same as stage_1 do.
    // axi_req.AW_lockType = 2'b00;
    // axi_req.AW_burstType = 2'b10;
    // axi_req.AW_protection = 3'b000;

    // axi_req.AW_addr = {
    // bus_req_o.addr = {
    //   stage_2_info.cache_lane_info[stage_2_next_lru_sel].ppn,
    //   delay_2_req.paddr[page_shift_len-1 : (word_shift_len+lane_len)],
    //   {(word_shift_len + lane_len) {1'b0}}
    // };
    // In the future, we may add support for changable length of burst transfer, but not today
    // axi_req.AW_len = lane_size - 1;
    // axi_req.AW_size = 3'b010;
    // axi_req.AW_cacheType = 4'b0000;
    // axi_req.AW_id = axi_id + 4;
    // axi_req.AW_valid = '0;
    // axi_req.AR_valid = '0;
    bus_req_o.valid = '0;
    bus_req_o.write = '0;

    // axi_req.DR_ready = 1'b0;
    // axi_req.DW_valid = '0;
    // axi_req.DW_last = '0;
    bus_req_o.data_ok = '0;
    bus_req_o.data_last = '0;

    // axi_req.DW_strobe = 4'b1111;
    bus_req_o.data_strobe = 4'b1111;
    // axi_req.DW_id = axi_id + 4;
    // axi_req.BW_ready = '0;
    case (fsm_state)
      S_WADR: begin
        // axi_req.AW_valid = '1;
        bus_req_o.valid = '1;
        bus_req_o.write = '1;

        if (delay_2_req.ctrl == `_CACHE_HIT_WRITEBACK_INVALID) begin
          // axi_req.AW_addr = {
          bus_req_o.addr = {
            stage_2_info.cache_lane_info[stage_2_hit_index].ppn,
            delay_2_req.paddr[page_shift_len-1 : (word_shift_len+lane_len)],
            {(word_shift_len + lane_len) {1'b0}}
          };
        end else if (delay_2_req.ctrl == `_CACHE_INDEX_INVALID) begin
          // axi_req.AW_addr = {
          bus_req_o.addr = {
            stage_2_info.cache_lane_info[delay_2_req.paddr[page_shift_len+$clog2(
                set_ass
            )-1 : page_shift_len]].ppn,
            delay_2_req.paddr[page_shift_len-1 : (word_shift_len+lane_len)],
            {(word_shift_len + lane_len) {1'b0}}
          };
        end else begin
          // axi_req.AW_addr = {
          bus_req_o.addr = {
            stage_2_info.cache_lane_info[stage_2_next_lru_sel].ppn,
            delay_2_req.paddr[page_shift_len-1 : (word_shift_len+lane_len)],
            {(word_shift_len + lane_len) {1'b0}}
          };
        end
      end
      S_RADR: begin
        // axi_req.AR_valid = 1'b1;
        bus_req_o.valid = '1;
      end
      S_WDAT: begin
        // axi_req.DW_valid = '1;
        // axi_req.DW_last  = &data_transfer_counter;
        bus_req_o.data_ok = '1;
        bus_req_o.data_last = &data_transfer_counter;
      end
      // S_PAW: begin
      //   axi_req.AW_valid = '1;
      //   axi_req.AW_len = '0;
      //   axi_req.AW_burstType = 2'b00;
      //   axi_req.AW_size = {1'b0, delay_2_req.size};
      // end
      S_PADR: begin
        // axi_req.AR_valid = 1'b1;
        bus_req_o.valid = '1;
        // axi_req.AR_len = (slot_2_8_byte) ? 2'd1 : '0;
        bus_req_o.burst_size = '0;
        // axi_req.AR_burstType = (slot_2_8_byte) ? 2'b10 : 2'b00;

        // axi_req.AR_addr = {delay_2_req.paddr[31:0]};
        // axi_req.AR_size = {1'b0, delay_2_req.size};
        bus_req_o.addr = {delay_2_req.paddr[31:0]};
        bus_req_o.data_size = delay_2_req.size;
      end
      S_RDAT: begin
        // axi_req.DR_ready = 1'b1;
        bus_req_o.data_ok = '1;
      end
      S_PDAT: begin
        // axi_req.DR_ready = 1'b1;
        bus_req_o.data_ok = '1;
      end
      // S_B: begin
      //   axi_req.BW_ready = '1;
      // end
    endcase
    if (uncached_fsm_machine_busy) begin
      // axi_req.DW_data = uncached_axi_req.DW_data;
      // axi_req.AW_burstType = uncached_axi_req.AW_burstType;
      // axi_req.AW_addr = uncached_axi_req.AW_addr;
      // axi_req.AW_len = uncached_axi_req.AW_len;
      // axi_req.AW_size = uncached_axi_req.AW_size;
      // axi_req.AW_valid = uncached_axi_req.AW_valid;
      // axi_req.DW_valid = uncached_axi_req.DW_valid;
      // axi_req.DW_last = uncached_axi_req.DW_last;
      // axi_req.DW_strobe = uncached_axi_req.DW_strobe;
      // axi_req.BW_ready = uncached_axi_req.BW_ready;
      bus_req_o = uncached_bus_req_o;
    end
  end

  logic [31:0] stage_2_read_result;
  // assign d_resp.data = stage_2_read_result;
  // assign r_data_o = stage_2_read_result;
  // 输出数据处理
	always_comb begin
		case(delay_2_req_type[1:0])
			`_MEM_TYPE_WORD: begin
				r_data_o = stage_2_read_result;
			end
			`_MEM_TYPE_HALF: begin
				if(paddr_o[1])
					r_data_o = {{16{(stage_2_read_result[31] & ~delay_2_req_type[2])}},stage_2_read_result[31:16]};
				else
					r_data_o = {{16{(stage_2_read_result[15] & ~delay_2_req_type[2])}},stage_2_read_result[15:0]};
			end
			`_MEM_TYPE_BYTE: begin
				if(paddr_o[1])
					if(paddr_o[0])
						r_data_o = {{24{(stage_2_read_result[31] & ~delay_2_req_type[2])}},stage_2_read_result[31:24]};
					else
						r_data_o = {{24{(stage_2_read_result[23] & ~delay_2_req_type[2])}},stage_2_read_result[23:16]};
				else
					if(paddr_o[0])
						r_data_o = {{24{(stage_2_read_result[15] & ~delay_2_req_type[2])}},stage_2_read_result[15:8]};
					else
						r_data_o = {{24{(stage_2_read_result[7 ] & ~delay_2_req_type[2])}},stage_2_read_result[7 :0]};
			end
			default: begin
				r_data_o = stage_2_read_result;
			end
		endcase
	end

  // assign d_resp.tlb_miss = '0;
  // assign d_resp.valid = delay_2_req.ctrl == `_CACHE_CTRL_WRITE || delay_2_req.ctrl == `_CACHE_CTRL_READ;
  // assign d_resp.vaddr = delay_2_req.paddr;
  assign paddr_o = delay_2_req.paddr;
  assign vaddr_o = delay_2_req.vaddr;
	assign w_data_o = w_req.data & {{8{w_req.byteen[3]}},{8{w_req.byteen[2]}},{8{w_req.byteen[1]}},{8{w_req.byteen[0]}}};

  // This block will describe cache data write logic.
  // All write is done in final stage, so we only need to controll it directly in stage 2
  always_comb begin
    stage_2_hit_index = '0;
    for (int i = 0; i < set_ass; i += 1) begin
      if (stage_2_hit_miss.hit[i]) stage_2_hit_index = i;
    end
  end
  logic [31:0] stage_2_passthrough_reg;
  always_ff @(posedge clk) begin
    // if (~rst_n) stage_2_passthrough_reg <= '0;
    // else 
    if (bus_resp_i.data_ok & (fsm_state == S_PDAT) & bus_resp_i.data_last)
      stage_2_passthrough_reg <= bus_resp_i.r_data;
  end
  assign stage_2_read_result = delay_2_req.passthrough ? stage_2_passthrough_reg : normal_data_resp_r_data[0][stage_2_hit_index];
  // assign slot_2_resp = delay_2_req.passthrough ? stage_2_passthrough_reg[1] : normal_data_resp_r_data[1][stage_2_hit_index];
  always_comb begin
    if (fsm_state == S_NORMAL) begin
      data_req_w_data = w_req.data;
      data_req_w_addr = delay_2_req.paddr[page_shift_len-1:word_shift_len];
      data_req_w_set_sel = stage_2_hit_index;
      data_req_w_enable = {4{(~(stage_2_hit_miss.miss | delay_2_req.passthrough)) && (delay_2_req.ctrl == `_CACHE_CTRL_WRITE) && (~request_clr_m2_i)}} & w_req.byteen;
    end else begin
      data_req_w_data = bus_resp_i.r_data;
      data_req_w_addr = {
        delay_2_req.paddr[page_shift_len-1 : word_shift_len+lane_len],
        data_transfer_counter[lane_len-1 : 0]
      };
      data_req_w_set_sel = stage_2_next_lru_sel;
      data_req_w_enable = (bus_resp_i.data_ok && (fsm_state == S_RDAT)) ? 4'b1111 : 4'b0000;
    end
  end

  // FSM_HIT_MISS MAINTAIN
  always_comb begin
    fsm_hit_miss = stage_2_hit_miss;
    fsm_hit_miss.miss = '0;
    fsm_hit_miss.hit[stage_2_next_lru_sel] = 1'b1;
  end

  // In this part, we discribe a fifo that do uncached write buffer.
  // Module instance begin
  uncached_write_req_t uncached_handling_req;
  logic uncached_full;
  logic uncached_empty;
  logic uncached_w_valid;
  logic uncached_r_valid;

  uncached_fifo #(
      .fifo_depth (64),
      .data_length($size(uncached_write_req_t))
  ) uncached_request_fifo (
      .clk(clk),
      .rst_n(rst_n),
      .r_valid(uncached_r_valid),
      .w_valid(uncached_w_valid),
      .data_in(uncached_req),
      .data_out(uncached_handling_req),
      .full(uncached_full),
      .empty(uncached_empty)
  );

  // fifo_fsm controlling logic
  always_comb begin
    uncached_req.req_data = w_req.data;
    uncached_req.req_addr = {delay_2_req.paddr[31:0]};
    uncached_req.req_size = {1'b0, delay_2_req.size};
    uncached_req.req_strobe = w_req.byteen;
    uncached_req_valid = ~stall_pipe && (delay_2_req.ctrl == `_CACHE_CTRL_WRITE) && delay_2_req.passthrough && ~request_clr_m2_i;
  end

  // Logic begin
  localparam int S_FIFO_WAIT = 0;
  // localparam int S_FIFO_AW = 1;  // To sppedup, we ensure AW-DW to working together.
  localparam int S_FIFO_ADDR = 1;
  // localparam int S_FIFO_DW = 2;  // We dont need to wait AW-READY, before we sent data-ready.
  localparam int S_FIFO_DATA = 2;
  // localparam int S_FIFO_BW = 3;  // We dont need to wait AW-READY, before we sent data-ready.

  logic [1:0] fifo_fsm_state;
  logic [1:0] fifo_fsm_next_state;

  always_ff @(posedge clk) begin
    if (~rst_n) fifo_fsm_state <= S_FIFO_WAIT;
    else fifo_fsm_state <= fifo_fsm_next_state;
  end

  always_comb begin
    case (fifo_fsm_state)
      S_FIFO_WAIT: begin
        if (~uncached_empty) begin
          fifo_fsm_next_state = S_FIFO_ADDR;
        end else begin
          fifo_fsm_next_state = S_FIFO_WAIT;
        end
      end
      S_FIFO_ADDR: begin
        if (bus_resp_i.ready) begin
          fifo_fsm_next_state = S_FIFO_DATA;
        end else begin
          fifo_fsm_next_state = S_FIFO_ADDR;
        end
      end
      S_FIFO_DATA: begin
        if (bus_resp_i.data_ok) begin
          if (~uncached_empty) begin
            fifo_fsm_next_state = S_FIFO_ADDR;
          end else begin
            fifo_fsm_next_state = S_FIFO_WAIT;
          end
        end else begin
          fifo_fsm_next_state = S_FIFO_DATA;
        end
      end
      // S_FIFO_BW: begin
      //   if (axi_resp.BW_valid) begin
      //     if (~uncached_empty) begin
      //       fifo_fsm_next_state = S_FIFO_AW;
      //     end else begin
      //       fifo_fsm_next_state = S_FIFO_WAIT;
      //     end
      //   end else begin
      //     fifo_fsm_next_state = S_FIFO_BW;
      //   end
      // end
      default: begin
        fifo_fsm_next_state = S_FIFO_WAIT;
      end
    endcase
  end

  // Controlling signal.
  always_comb begin
    uncached_fsm_machine_busy = ~uncached_empty;
    uncached_fsm_machine_full = uncached_full;
    uncached_w_valid = uncached_req_valid & ~uncached_full;
    uncached_r_valid = '0;
    case (fifo_fsm_state)
      S_FIFO_WAIT: begin
        uncached_r_valid = ~uncached_empty;
      end
      S_FIFO_ADDR: begin
        uncached_r_valid = '0;
        uncached_fsm_machine_busy = 1'b1;
      end
      S_FIFO_DATA: begin
        uncached_r_valid = (~uncached_empty) & bus_resp_i.data_ok;
        uncached_fsm_machine_busy = 1'b1;
      end
      // S_FIFO_BW: begin
      //   uncached_r_valid = (~uncached_empty) && axi_resp.BW_valid;
      //   uncached_fsm_machine_busy = 1'b1;
      // end
    endcase
  end

  // Axi signal.
  always_comb begin
    // Write back allocation:
    // uncached_axi_req.DW_data = uncached_handling_req.req_data;
    uncached_bus_req_o.w_data = uncached_handling_req.req_data;

    // The AW ppn addr is from victim tag, index tag is the same as stage_1 do.
    // uncached_axi_req.AW_burstType = 2'b00;
    // uncached_axi_req.AW_addr = uncached_handling_req.req_addr;
    uncached_bus_req_o.addr = uncached_handling_req.req_addr;

    // In the future, we may add support for changable length of burst transfer, but not today
    // uncached_axi_req.AW_len = '0;
    uncached_bus_req_o.burst_size = 4'b0;
    // uncached_axi_req.AW_size = uncached_handling_req.req_size;
    uncached_bus_req_o.data_size = uncached_handling_req.req_size;

    // uncached_axi_req.AW_valid = fifo_fsm_state == S_FIFO_AW;
    uncached_bus_req_o.valid = fifo_fsm_state == S_FIFO_ADDR;
    uncached_bus_req_o.write = fifo_fsm_state == S_FIFO_ADDR;
    // uncached_axi_req.DW_valid = fifo_fsm_state == S_FIFO_DATA;
    // uncached_axi_req.DW_last = fifo_fsm_state == S_FIFO_DATA;
    uncached_bus_req_o.data_ok = fifo_fsm_state == S_FIFO_DATA;
    uncached_bus_req_o.data_last = fifo_fsm_state == S_FIFO_DATA;
    // uncached_axi_req.DW_strobe = uncached_handling_req.req_strobe;
    uncached_bus_req_o.data_strobe = uncached_handling_req.req_strobe;
    // uncached_axi_req.BW_ready = fifo_fsm_state == S_FIFO_BW ||
    //                             fifo_fsm_state == S_FIFO_DW || 
    //                             fifo_fsm_state == S_FIFO_AW;
  end

endmodule : cached_lsu