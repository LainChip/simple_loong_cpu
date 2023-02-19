`include "common.svh"
`include "decoder.svh"

/*--JSON--{"module_name":"icache","module_ver":"3","module_type":"module"}--JSON--*/
module icache #(
	parameter int FETCH_SIZE = 2,               // 只可选择 1 / 2 / 4
	parameter int ATTACHED_INFO_WIDTH = 32,     // 用于捆绑bpu输出的信息，跟随指令流水
    // parameter int LANE_SIZE = 4,             // 指示一条cache line中存有几条指令 -- fixed为4,不可配置
    parameter int WAY_CNT = 2,                  // 指示cache的组相联度
    parameter bit BUFFERED_DECODER = 1'b1,
    parameter bit ENABLE_PLRU = 1'b0
)(
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
    input  logic [1:0] cacheop_i, // 输入两位的cache控制信号
    input  logic cacheop_valid_i, // 输入的cache控制信号有效
    output logic cacheop_ready_o,

	input  logic [31:0]vpc_i,
	input  logic [FETCH_SIZE - 1 : 0] valid_i,
	input  logic [ATTACHED_INFO_WIDTH - 1 : 0] attached_i,

	// MMU 访问信号
	output logic[31:0] mmu_req_vpc_o,
	input mmu_s_resp_t mmu_resp_i,

	output logic [31:0]vpc_o,
	output logic [31:0]ppc_o,
	output logic [FETCH_SIZE - 1 : 0] valid_o,
	output logic [ATTACHED_INFO_WIDTH - 1 : 0] attached_o,
    output logic [FETCH_SIZE - 1 : 0][31:0] inst_o,
    (* mark_debug="true" *) output fetch_excp_t fetch_excp_o,
	// output decode_info_t [FETCH_SIZE - 1 : 0] decode_output_o,

	input  logic ready_i, // FROM QUEUE
	output logic ready_o, // TO NPC/BPU
	input  logic clr_i,

    input logic bus_busy_i,

	(* mark_debug="true" *) output cache_bus_req_t bus_req_o,
	(* mark_debug="true" *) input cache_bus_resp_t bus_resp_i,
    input uncached_i
    // input trans_en_i
);

    // 全局控制信号
    logic stall;        // TODO CONNECTION
    logic delay_stall;  // TODO CONNECTION

    typedef struct packed {
        logic valid;
        logic[19:0] ppn;
    } tag_t;

    // 数据通路
    logic [31:0] f1_vaddr;               // TODO CONNECTION
    logic [11:2] ram_rw_addr;            // TODO CONNECTION
    logic        ram_we_data,ram_we_tag; // TODO CONNECTION
    logic [WAY_CNT - 1 : 0] ram_we_mask; // TODO CONNECTION

    tag_t        ram_w_tag;              // TODO CONNECTION
    logic [31:0] ram_w_data;             // TODO CONNECTION

    tag_t [WAY_CNT - 1 : 0]                           ram_r_tag;  // F1 STAGE
    logic [WAY_CNT - 1 : 0][FETCH_SIZE - 1 : 0][31:0] ram_r_data; // F1 STAGE

    for(genvar way_id = 0 ; way_id < WAY_CNT ; way_id += 1) begin
        logic [FETCH_SIZE - 1 : 0][31:0] raw_r_data;
        logic [20:0] raw_r_tag;
        icache_datapath datapath(
            .clk(clk),
            .rst_n(rst_n),
            .data_we_i(ram_we_data && ram_we_mask[way_id]),
            .tag_we_i (ram_we_tag  && ram_we_mask[way_id]),
            .addr_i(ram_rw_addr),

            .data_o(raw_r_data),
            .data_i(ram_w_data),

            .tag_o(raw_r_tag),
            .tag_i(ram_w_tag)
        );

        // 添加寄存器, 进行数据转发和暂停的情况
        // 前者为组合逻辑, 后者为寄存器, 在暂停时候保存F1级别的数据并进行转发维护
        // 前者为维护好的数据
        logic [FETCH_SIZE - 1 : 0][31:0] f1_data,f1_reg_data;
        tag_t                            f1_tag ,f1_reg_tag ;

        // 转发源
        logic [31:0] f2_w_data,buf_w_data;
        tag_t        f2_w_tag ,buf_w_tag ;

        // 转发地址
        logic[11:2]  f1_r_addr ,f2_w_addr , buf_w_addr;
        logic        f2_data_we,buf_data_we,f2_tag_we,buf_tag_we;

        // 数据流水
        assign f1_r_addr  = f1_vaddr[11:2];
        assign f2_w_addr  = ram_rw_addr;
        assign f2_data_we = ram_we_data && ram_we_mask[way_id];
        assign f2_we_tag  = ram_we_tag  && ram_we_mask[way_id];
        assign f2_w_data  = ram_w_data;
        assign f2_w_tag   = ram_w_tag ;
        always_ff @(posedge clk) begin
            buf_w_addr   <= f2_w_addr;
            buf_data_we  <= f2_data_we;
            buf_tag_we   <= f2_tag_we;
            buf_w_tag    <= f2_w_tag;
            buf_w_data   <= f2_w_data;
        end

        // stall 处理
        always_ff @(posedge clk) begin
            f1_reg_data <= f1_data;
            f1_reg_tag  <= f1_tag;
        end

        // 前馈, 保证F2级产生的写请求在F1级别可见
        always_comb begin
            f1_tag = delay_stall ? f1_reg_tag : raw_r_tag;
            if(buf_tag_we && (buf_w_addr[11:4] == f1_r_addr[11:4])) begin
                f1_tag = buf_w_tag;
            end
        end
        always_comb begin
            f1_data = delay_stall ? f1_reg_data : raw_r_data;
            if(buf_data_we && (buf_w_addr[11:2+$clog2(FETCH_SIZE)] == f1_r_addr[11:2+$clog2(FETCH_SIZE)])) begin
                f1_data[buf_w_addr[2+$clog2(FETCH_SIZE)-1:2]] = buf_w_data;
            end
        end
        assign ram_r_data[way_id] = f1_data;
        assign ram_r_tag[way_id]  = f1_tag ;
    end

    // 第二阶段数据, 根据第二阶段的数据构造状态机
    // 地址
    logic [31:0] paddr,vaddr; // TODO

    // 缓存状态
    tag_t [WAY_CNT - 1 : 0] tag;
    logic [WAY_CNT - 1 : 0][FETCH_SIZE - 1 : 0][31:0] data;

    logic [$clog2(WAY_CNT) - 1 : 0] direct_sel_index;
    logic [FETCH_SIZE - 1 : 0][31:0] sel_data;

    // 比较信息

endmodule
