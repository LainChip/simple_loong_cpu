`include "common.svh"
`include "decoder.svh"

/*--JSON--{"module_name":"icache","module_ver":"2","module_type":"module"}--JSON--*/
module icache #(
	parameter int FETCH_SIZE = 2,               // 只可选择 1 / 2 / 4
	parameter int ATTACHED_INFO_WIDTH = 32,     // 用于捆绑bpu输出的信息，跟随指令流水
    // parameter int LANE_SIZE = 4,             // 指示一条cache line中存有几条指令 -- fixed为4,不可配置
    parameter int WAY_CNT = 4,                  // 指示cache的组相联度
    parameter bit BUFFERED_DECODER = 1'b1
)(
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
    input  logic [1:0] cacheop_i, // 输入两位的cache控制信号
    input  logic cacheop_valid_i, // 输入的cache控制信号有效
    output logic cacheop_ready_o,

	input  logic [31:0]vpc_i,
	input  logic [FETCH_SIZE - 1 : 0] valid_i,
	input  logic [ATTACHED_INFO_WIDTH - 1 : 0] attached_i,

	output logic [31:0]vpc_o,
	output logic [31:0]ppc_o,
	output logic [FETCH_SIZE - 1 : 0] valid_o,
	output logic [ATTACHED_INFO_WIDTH - 1 : 0] attached_o,
	output decode_info_t [FETCH_SIZE - 1 : 0] decode_output_o,

	input  logic ready_i, // FROM QUEUE
	output logic ready_o, // TO NPC/BPU
	input  logic clr_i,

	output cache_bus_req_t bus_req_o,
	input cache_bus_resp_t bus_resp_i
);

// 当FIFO没有就绪时候（已满），将stall拉高
logic stall;
assign stall = ~ready_i;

typedef struct packed {
    logic valid;
    logic dirty; // 对于 icache来说，这一位是无效的
    logic[19:0] page_index;
} tag_t;

// 解码阶段的信息,不需要重复声明，即为output的那几个信号

// 第二阶段的信息
logic[31:0] va,pa;
logic valid_req;
logic[FETCH_SIZE - 1 : 0] fetch_valid;
logic[ATTACHED_INFO_WIDTH - 1 : 0] fetch_attached;
logic inv,fetched,uncached,cache_op,transfer_done;
logic[1:0] cache_op_type;

// 第一阶段的信息
logic[31:0] va_early;
logic valid_req_early,cache_op_early;
logic[FETCH_SIZE - 1 : 0] fetch_valid_early;
logic[ATTACHED_INFO_WIDTH - 1 : 0] fetch_attached_early;
logic[1:0] cache_op_type_early;

// FSM 控制信号 (独热码)
logic [4:0] fsm_state,fsm_state_next;
localparam logic[4:0] STATE_NORM = 5'b00001;
localparam logic[4:0] STATE_INVA = 5'b00010;
localparam logic[4:0] STATE_ADDR = 5'b00100;
localparam logic[4:0] STATE_FETC = 5'b01000;
localparam logic[4:0] STATE_SYNC = 5'b10000;

// 指令fetch的计数器,最高位有效时，表示fetch已结束。
logic [1:0] fetch_cnt;

// 第一阶段， 在NORMAL时候获得tag 和 data
// 在非NORMAL的时候，由状态机控制写入，在FETCH阶段读取，
// 此模块的地址在NORMAL和非NORMAL时候，有不同的控制源，
// 此模块的写数据，写tag相关控制信号唯一。

logic[19:0] page_index_raw; // TODO 连接到tlb, 从va_early 中计算
logic [11:0] datapath_addr;
logic[31:0] w_data;
tag_t w_tag;
logic handling;

// 地址及控制信息流水
always_ff @(posedge clk) begin
    if(~handling & ~stall) begin
        va_early <= vpc_i;
        fetch_valid_early <= valid_i;
        fetch_attached_early <= attached_i;
        valid_req_early <= (|valid_i) | cacheop_valid_i;
        cache_op_type_early <= cacheop_i;
        cache_op_early <= cacheop_valid_i;
        
        va <= va_early;
        pa <= {page_index_raw,va_early[11:0]};
        fetch_valid <= fetch_valid_early;
        fetch_attached <= fetch_attached_early;
        valid_req <= valid_req_early/*& TODO TLB VALID | cacheop */;
        cache_op_type <= cache_op_type_early;
        cache_op <= cache_op_early;
        uncached <= 1'b0 /*TODO TLB UNCACHED*/;

        vpc_o <= va;
        ppc_o <= pa;
        valid_o <= fetch_valid;
        attached_o <= fetch_attached;
    end
end

// TLB 相关的逻辑
assign page_index_raw = va_early[31:12];

for (genvar way_id = 0 ; way_id < WAY_CNT; way_id += 1) begin : way
    // 对于每一路，共有的物理地址输入
    logic[19:0] page_index;

    // 下面这些是唯一的控制信号，直接由状态机在缺失 或者控制指令到来时进行控制
    logic data_we,tag_we;

    // 下面这些是需要选择的控制信号，有多个控制源，由状态机进行选择
    // 这两个信号是选择出来的信号，直接进行流水即可。
    logic[FETCH_SIZE - 1 : 0][31:0] r_data,r_data_raw;
    tag_t r_tag,r_tag_raw;
    logic sel;

    icache_datapath#(
        .FETCH_SIZE(FETCH_SIZE)
    ) icache_datapath_module(
        .clk(clk),
        .rst_n(rst_n),

        .data_we_i(data_we),
        .tag_we_i(tag_we),
        .addr_i(datapath_addr),

        .data_o(r_data_raw),
        .data_i(w_data),

        .tag_o(r_tag_raw),
        .tag_i(w_tag)
    );

    always_ff@(posedge clk) begin
        if(~handling & ~stall) begin
            r_data <= r_data_raw;
            r_tag <= r_tag_raw;
            page_index <= page_index_raw;
        end
    end

    // 路选择逻辑
    assign sel = (page_index == r_tag.page_index) & r_tag.valid;
end

// 输出逻辑
logic[FETCH_SIZE - 1 : 0][31:0] inst_raw, inst;
always_comb begin
    inst_raw = '0;
    for(int way_id = 0; way_id < WAY_CNT ; way_id += 1) begin
        inst_raw |= {32{way[way_id].sel}} & way[way_id].r_data;
    end
end
always_ff @(posedge clk) begin
    if(~rst_n) begin
        inst <= '0;
    end else begin
        // TODO: FSM CONTROLLING LOGIC.
        inst <= inst_raw;
    end
end

// REFILL 逻辑，整体状态机逻辑在此实现

// PLRU 逻辑，使用 plru_tree 模块维护每个cache行的lru信息
// 共计256个cache行，每行4word = 1k个word 共计每路4k大小
for(genvar cache_index = 0; cache_index < 256; cache_index += 1) begin : cache_line
    logic[WAY_CNT - 1 : 0] use_vec;
    logic[WAY_CNT - 1 : 0] sel_vec;
    plru_tree #(
        .ENTRIES(WAY_CNT)
    )plru_module(
        .clk(clk),
        .rst_n(rst_n),
        .used_i(use_vec),
        .plru_o(sel_vec)
    );
end

// INVALID 逻辑
always_comb begin
    inv = 1'b1;
    for(int way_id = 0 ; way_id < WAY_CNT ;way_id += 1) begin
        inv &= ~way[way_id].sel;
    end
end

// FSM 状态转移逻辑
always_comb begin
    fsm_state_next = fsm_state;
    case(fsm_state) begin
        STATE_NORM: begin
            if(cache_op) begin
                if(cache_op_type[1]) begin // HIT INVALIDATE
                    if(~inv) begin
                        fsm_state_next = STATE_INVA;
                    end
                end else begin
                    fsm_state_next = STATE_INVA;
                end
            end
            else if(~fetched) begin
                if(uncached | inv) begin
                    fsm_state_next = STATE_ADDR;
                end
            end
        end
        STATE_ADDR: begin
            if(bus_resp_i.ready) begin
				fsm_state_next = STATE_FETC;
            end
        end
        STATE_FETC: begin
			if(transfer_done) begin
				fsm_state_next = STATE_SYNC;
			end
        end
        STATE_INVA: begin
            fsm_state_next = STATE_SYNC;
        end
        STATE_SYNC: begin
            fsm_state_next = STATE_NORM;
        end
        default: begin
            fsm_state_next = STATE_NORM;
        end
    end
end

// 由FSM控制的内部维护信号管理
always_comb begin
    datapath_addr = vpc_i[11:2];
    w_data = bus_resp_i.r_data;
    w_tag.valid = 1'b1;
    w_tag.dirty = 1'b0;
    w_tag.page_index = pa[31:12];

    for(int way_id = 0; way_id < WAY_CNT ; way_id += 1) begin
        way[way_id].data_we = '0;
        way[way_id].tag_we = '0;
    end
    for(int index_id = 0; index_id < 256;index_id += 1) begin
        cache_line[index_id].use_vec = '0;
    end
    if(fsm_state == STATE_NORM && fsm_state == fsm_state_next) begin // ONLY UPDATE ON HIT STATE
        for(int way_id = 0; way_id < WAY_CNT;way_id += 1) begin
            cache_line[va[11:4]].use_vec[way_id] |= way[way_id].sel;
        end
        if(stall) begin
            datapath_addr = va_early[11:2];
        end
    end else if(fsm_state == STATE_INVA) begin
        if(cache_op_type == 2'b00) begin
            // STORE TAG
            datapath_addr = va[11:2];
            w_tag = '0;
            way[va[$clog2(WAY_CNT) - 1 : 0]].tag_we = 1'b1;
        end else if(cache_op_type == 2'b01) begin
            // INDEX INVALIDATE
            datapath_addr = va[11:2];
            w_tag.valid = '0;
            way[va[$clog2(WAY_CNT) - 1 : 0]].tag_we = 1'b1;
        end else begin
            // HIT INVALIDATE
            datapath_addr = va[11:2];
            w_tag.valid = '0;
            for(int way_id = 0; way_id < WAY_CNT; way_id += 1) begin
                way[way_id].tag_we |= way[way_id].sel;
            end
        end
    end else if(fsm_state == STATE_FETC) begin
        datapath_addr = {va[11:4],fetch_cnt[1:0]};
        for(int way_id = 0; way_id < WAY_CNT; way_id += 1) begin
            way[way_id].data_we |= cache_line[va[11:4]].sel_vec[way_id] & bus_resp_i.data_ok;
            way[way_id].tag_we  |= cache_line[va[11:4]].sel_vec[way_id] /*& bus_resp_i.data_last & bus_resp_i.data_ok TODO: JUDGE WHETHER WE NEED THIS*/;
        end
    end else if(fsm_state == STATE_SYNC) begin
        datapath_addr = va_early[11:2];
    end
end

// 由FSM控制的总线信号
always_comb begin
	bus_req_o.valid = fsm_state == STATE_ADDR;
	bus_req_o.write = '0;
	bus_req_o.burst = ~uncached;
	bus_req_o.cached = ~uncached;
	bus_req_o.addr = {pa[31:4], 4'b0000};

	bus_req_o.w_data = '0;
	bus_req_o.data_strobe = '0;
	bus_req_o.data_ok = fsm_state == STATE_FETC;
	bus_req_o.data_last = '0;
end

// 由FSM控制的fetch counter 逻辑
always_ff @(posedge clk) begin
    if(fsm_state == STATE_FETC) begin
        fetch_cnt <= {fetch_cnt[1] ^ (fetch_cnt[0] & bus_resp_i.data_ok), fetch_cnt[0] ^ bus_resp_i.data_ok};
    end else begin
        fetch_cnt <= '0;
    end
end

// 由FSM控制的handling 逻辑
assign handling = (fsm_state != STATE_NORM) || (fsm_state != fsm_state_next);

// 由FSM控制的fetched，transfer_done逻辑
assign transfer_done = bus_resp_i.data_ok & bus_resp_i.data_last;
always_ff @(posedge clk) begin
    if(fsm_state == STATE_SYNC) begin
        fetched <= 1'b1;
    end else if(~stall)begin
        fetched <= 1'b0;
    end
end

endmodule