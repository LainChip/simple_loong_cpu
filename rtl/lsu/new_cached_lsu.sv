`include "common.svh"
`include "decoder.svh"
`include "lsu_types.svh"

module lsu #(
    parameter int WAY_CNT = 2,
    parameter bit ENABLE_PLRU = 1'b0
) (
    input logic clk,
    input logic rst_n,
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
  input logic request_clr_hint_m2_i,
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

    typedef struct packed {
        logic valid;
        logic dirty;
        logic[19:0] ppn;
    } tag_t;

    // 数据通路
    logic [11:2]ram_raddr;
    logic [11:2]ram_waddr;
    logic [3:0] ram_we_data;             // 写数据位使能
    logic ram_we_tag;                    // 写tag使能
    logic [WAY_CNT - 1 : 0] ram_we_mask; // 写使能mask

    tag_t        ram_w_tag;              // 待写入的tag
    logic [31:0] ram_w_data;             // 待写入的data

    tag_t [WAY_CNT - 1 : 0]       ram_r_tag;
    logic [WAY_CNT - 1 : 0][31:0] ram_r_data;

    for(genvar way_id = 0 ; way_id < WAY_CNT ; way_id += 1) begin
        logic [3:0][7:0] raw_rdata;
        logic [21:0]     raw_rtag;
        dcache_datapath datapath(
            .clk(clk),
            .rst_n(rst_n),
            .data_we_i(ram_we_data & {4{ram_we_mask[way_id]}}),
            .tag_we_i(ram_we_tag & ram_we_mask[way_id]),
            .r_addr_i(ram_raddr),
            .w_addr_i(ram_waddr),
            .data_o(raw_rdata),
            .data_i(ram_w_data),

            .tag_o(raw_rtag),
            .tag_i(ram_w_tag)
        );
        logic [3:0][7:0] m1_data,m2_data,wb_data;
        tag_t            m2_tag,wb_tag;

        logic [11:2] m1_r_addr,m2_w_addr,wb_w_addr;
        logic [3:0]  m2_w_byteen,wb_w_byteen;
        logic        m2_tag_we,wb_tag_we;

        // 数据流水
        always_ff @(posedge clk) begin
            m1_r_addr <= ram_raddr;
        end
        assign m2_w_addr = ram_waddr;
        assign m2_w_byteen = ram_we_data & {4{ram_we_mask[way_id]}};
        assign m2_tag_we = ram_we_tag & ram_we_mask[way_id];
        always_ff @(posedge clk) begin
            wb_w_addr   <= m2_w_addr;
            wb_w_byteen <= m2_w_byteen;
            wb_tag_we   <= m2_tag_we;
        end

        // 前馈，保证M2级产生的请求可以被正确的转发到EX,M1级
        // M2级别的写请求对EX,M1不可见，WB级别的请求对M1不可见，故在M1对M2和WB级的请求进行转发，优先级M2高于WB
        always_comb begin
            ram_r_tag[way_id] = raw_rtag;
            if(wb_tag_we && (wb_w_addr[11:4] == m1_r_addr[11:4])) begin
                ram_r_tag[way_id] = wb_tag;
            end
            if(m2_tag_we && (m2_w_addr[11:4] == m1_r_addr[11:4])) begin
                ram_r_tag[way_id] = m2_tag;
            end
        end
        for(genvar byte_id = 0; byte_id < 4 ; byte_id += 1) begin
            always_comb begin
                m1_data[byte_id] = raw_rdata[byte_id];
                if(wb_w_byteen[byte_id] && (wb_w_addr == m1_r_addr)) begin
                    m1_data[byte_id] = wb_data[byte_id];
                end
                if(m2_w_byteen[byte_id] && (m2_w_addr == m1_r_addr)) begin
                    m1_data[byte_id] = m2_data[byte_id];
                end
            end
        end
        assign ram_r_data[way_id] = m1_data;
    end

    // 第二阶段数据，根据第二阶段数据构建状态机
    // 地址
    logic [31:0] paddr,vaddr;
    // 缓存状态
    tag_t [WAY_CNT - 1 : 0] tag;
    logic [WAY_CNT - 1 : 0][31:0] data;

    // 比较信息
    logic [WAY_CNT - 1 : 0] match;

    // 控制信息,独热编码
    logic ctrl_read,ctrl_write,ctrl_hit_wb,ctrl_invalid_wb,ctrl_invalid;

    // 控制信息，伪随机数
    logic random_taken;

    // 控制信息，主状态机
    localparam logic[3:0] S_NORMAL    = 4'd0;
    localparam logic[3:0] S_WAIT_BUS  = 4'd1;
    localparam logic[3:0] S_RADR      = 4'd2;
    localparam logic[3:0] S_RDAT      = 4'd3;
    localparam logic[3:0] S_WADR      = 4'd4;
    localparam logic[3:0] S_WDAT      = 4'd5;
    localparam logic[3:0] S_PRADR     = 4'd6;
    localparam logic[3:0] S_PRDAT     = 4'd7;
    localparam logic[3:0] S_WAIT_FULL = 4'd8;
    logic[3:0] fsm_state,fsm_state_next;
    always_ff @(posedge clk) begin
        if(~rst_n) fsm_state <= S_NORMAL;
        else fsm_state <= fsm_state_next;
    end


    // 控制信息，写回状态机
    localparam logic[1:0] S_FEMPTY = 2'd0;
    localparam logic[1:0] S_FADR   = 2'd1;
    localparam logic[1:0] S_FDAT   = 2'd2;
    logic[1:0] fifo_fsm_state,fifo_fsm_next_state;
    always_ff @(posedge clk) begin
        if(~rst_n) fifo_fsm_state <= S_FEMPTY;
        else fifo_fsm_state <= fifo_fsm_next_state;
    end

    // cached 信息
    logic uncached;

    // 生成比较信息
    for(genvar way_id = 0; way_id < WAY_CNT ; way_id += 1) begin
        assign match[way_id] = tag[way_id].valid && (tag[way_id].ppn == paddr[31:12]);
    end

endmodule