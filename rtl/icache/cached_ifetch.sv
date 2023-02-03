`include "common.svh"
`include "decoder.svh"

/*--JSON--{"module_name":"icache","module_ver":"2","module_type":"module"}--JSON--*/
module icache #(
	parameter int FETCH_SIZE = 2,               // 只可选择 1 / 2 / 4
	parameter int ATTACHED_INFO_WIDTH = 32,     // 用于捆绑bpu输出的信息，跟随指令流水
    // parameter int LANE_SIZE = 4,             // 指示一条cache line中存有几条指令 -- fixed为4,不可配置
    parameter int WAY_CNT = 4,                  // 指示cache的组相联度
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
    output fetch_excp_t fetch_excp_o,
	// output decode_info_t [FETCH_SIZE - 1 : 0] decode_output_o,

	input  logic ready_i, // FROM QUEUE
	output logic ready_o, // TO NPC/BPU
	input  logic clr_i,

	output cache_bus_req_t bus_req_o,
	input cache_bus_resp_t bus_resp_i
    // input trans_en_i
);

// 当FIFO没有就绪时候（已满），将stall拉高
logic stall,stall_delay;
typedef struct packed {
    logic valid;
    logic dirty; // 对于 icache来说，这一位是无效的
    logic[19:0] page_index;
} tag_t;

// 第二阶段的信息
logic[1:0]  plv;
mmu_s_resp_t mmu_resp;
logic trans_en,trans_en_i;
logic[31:0] va,pa;
logic valid_req;
logic[FETCH_SIZE - 1 : 0] fetch_valid;
logic[ATTACHED_INFO_WIDTH - 1 : 0] fetch_attached;
logic inv,fetched,uncached,cache_op,transfer_done;
logic[1:0] cache_op_type;

// 第二阶段的异常
logic fetch_excp, fetch_excp_adef, fetch_excp_tlbr, fetch_excp_pif, fetch_excp_ppi;

// 第一阶段的信息
logic[31:0] va_early;
logic valid_req_early,cache_op_early;
logic[FETCH_SIZE - 1 : 0] fetch_valid_early;
logic[ATTACHED_INFO_WIDTH - 1 : 0] fetch_attached_early;
logic[1:0] cache_op_type_early;

// 第一阶段的异常
logic fetch_excp_adef_early;

// FSM 控制信号 (独热码)
logic [5:0] fsm_state,fsm_state_next;
localparam logic[5:0] STATE_NORM = 6'b000001;
localparam logic[5:0] STATE_INVA = 6'b000010;
localparam logic[5:0] STATE_ADDR = 6'b000100;
localparam logic[5:0] STATE_FETC = 6'b001000;
localparam logic[5:0] STATE_SYNC = 6'b010000;
localparam logic[5:0] STATE_SYN2 = 6'b100000;

// 指令fetch的计数器,最高位有效时，表示fetch已结束。
logic [1:0] fetch_cnt;

// 第一阶段， 在NORMAL时候获得tag 和 data
// 在非NORMAL的时候，由状态机控制写入，在FETCH阶段读取，
// 此模块的地址在NORMAL和非NORMAL时候，有不同的控制源，
// 此模块的写数据，写tag相关控制信号唯一。

logic[19:0] page_index_raw; // TODO 连接到tlb, 从va_early 中计算
logic [11:2] datapath_addr;
logic[31:0] w_data;
tag_t w_tag;
logic handling;

assign stall = ~ready_i | handling;
assign ready_o = ~stall & ~cacheop_valid_i;

// 地址及控制信息流水
always_ff @(posedge clk) begin
    if(clr_i) begin
        fetch_valid_early <= '0;
        fetch_excp_adef_early <= '0;
        valid_req_early <= '0;
        fetch_valid <= '0;
        valid_req <= '0;
        // valid_o <= '0;
    end else if(~stall) begin
        va_early <= vpc_i;
        fetch_excp_adef_early <= |vpc_i[1:0];
        fetch_valid_early <= valid_i;
        fetch_attached_early <= attached_i;
        valid_req_early <= ((|valid_i) & ready_o) | cacheop_valid_i;
        cache_op_type_early <= cacheop_i;
        cache_op_early <= cacheop_valid_i;
        
        va <= va_early;
        mmu_resp <= mmu_resp_i;
        trans_en <= trans_en_i;
 
        // fetch_excp <= fetch_excp_adef_early;
        fetch_excp_adef <= fetch_excp_adef_early;
        pa <= {page_index_raw,va_early[11:0]};
        fetch_valid <= fetch_valid_early;
        fetch_attached <= fetch_attached_early;
        valid_req <= valid_req_early/*& TODO TLB VALID | cacheop */;
        cache_op_type <= cache_op_type_early;
        cache_op <= cache_op_early;
        uncached <= 1'b0 /*TODO TLB UNCACHED*/;

        // vpc_o <= va;
        // ppc_o <= pa;
        // valid_o <= fetch_valid;
        // attached_o <= fetch_attached;
    end
end

assign vpc_o = va;
assign ppc_o = pa;
assign valid_o = fetch_valid & {FETCH_SIZE{~stall}};
assign attached_o = fetch_attached;

logic [WAY_CNT - 1 : 0] sel,data_we,tag_we;
tag_t [WAY_CNT - 1 : 0] r_tag;
logic [WAY_CNT - 1 : 0][FETCH_SIZE - 1 : 0][31:0] r_data;
for (genvar way_id = 0 ; way_id < WAY_CNT; way_id += 1) begin : way
    // 对于每一路，共有的物理地址输入
    logic[19:0] page_index;

    // 下面这些是唯一的控制信号，直接由状态机在缺失 或者控制指令到来时进行控制
    // logic data_we,tag_we;

    // 下面这些是需要选择的控制信号，有多个控制源，由状态机进行选择
    // 这两个信号是选择出来的信号，直接进行流水即可。
    logic[FETCH_SIZE - 1 : 0][31:0] r_data_raw;
    tag_t r_tag_raw;

    icache_datapath#(
        .FETCH_SIZE(FETCH_SIZE)
    ) icache_datapath_module(
        .clk(clk),
        .rst_n(rst_n),

        .data_we_i(data_we[way_id]),
        .tag_we_i(tag_we[way_id]),
        .addr_i(datapath_addr[11:2]),

        .data_o(r_data_raw),
        .data_i(w_data),

        .tag_o(r_tag_raw),
        .tag_i(w_tag)
    );

    always_ff@(posedge clk) begin
        if(~stall || fsm_state == STATE_SYNC || fsm_state == STATE_SYN2) begin
            r_data[way_id] <= r_data_raw;
            r_tag[way_id] <= r_tag_raw;
            page_index <= page_index_raw;
        end
    end

    // 路选择逻辑
    assign sel[way_id] = (page_index == r_tag[way_id].page_index) & r_tag[way_id].valid;
end

// 输出逻辑
logic[FETCH_SIZE - 1 : 0][31:0] inst_raw, inst;
always_comb begin
    inst_raw = '0;
    for(int way_id = 0; way_id < WAY_CNT ; way_id += 1) begin
        inst_raw |= {(FETCH_SIZE*32){sel[way_id]}} & r_data[way_id];
    end
end
always_ff @(posedge clk) begin
    if(fsm_state == STATE_NORM && ~stall_delay) 
        inst <= inst_raw;
    else if(fsm_state == STATE_FETC && fetch_cnt[1] == pa[3]) 
        inst[fetch_cnt[0]] <= bus_resp_i.r_data;
end
always_ff @(posedge clk) begin
    stall_delay <= stall;
end
// for(genvar fetch_id = 0; fetch_id < FETCH_SIZE; fetch_id += 1) begin
// 	decoder decoder_module(
// 		.inst_i(inst[fetch_id]),
// 		.decode_info_o(decode_buf[fetch_id]),
// 		.inst_string_o(/*NC*/)
// 	);
// end
assign inst_o = (fetch_excp) ? '0 : ((stall_delay) ? inst : inst_raw);

// REFILL 逻辑，整体状态机逻辑在此实现

// PLRU 逻辑，使用 plru_tree 模块维护每个cache行的lru信息
// 共计256个cache行，每行4word = 1k个word 共计每路4k大小
logic[255:0][WAY_CNT - 1 : 0] use_vec;
logic[255:0][WAY_CNT - 1 : 0] sel_vec;
logic [$clog2(WAY_CNT) - 1 : 0]lfsr_sel_vec;
if(ENABLE_PLRU) begin
    for(genvar cache_index = 0; cache_index < 256; cache_index += 1) begin : cache_line
        plru_tree #(
            .ENTRIES(WAY_CNT)
        )plru_module(
            .clk(clk),
            .rst_n(rst_n),
            .used_i(use_vec[cache_index]),
            .plru_o(sel_vec[cache_index])
        );
    end
end else begin
    lfsr #(
        .LfsrWidth((8 * $clog2(WAY_CNT)) >= 64 ? 64 : (8 * $clog2(WAY_CNT))),
        .OutWidth($clog2(WAY_CNT))
    ) lfsr (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(fsm_state == STATE_SYN2),
        .out_o(lfsr_sel_vec)
    );
end

// INVALID 逻辑
always_comb begin
    inv = 1'b1;
    for(int way_id = 0 ; way_id < WAY_CNT ;way_id += 1) begin
        inv &= ~sel[way_id];
    end
end

// FSM 状态转移逻辑
always_comb begin
    fsm_state_next = fsm_state;
    case(fsm_state)
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
            else if(~fetched & valid_req) begin
                if((uncached | inv) & ~fetch_excp) begin
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
            fsm_state_next = STATE_SYN2;
        end
        default: begin
            fsm_state_next = STATE_NORM;
        end
    endcase
end

// 由FSM控制的内部维护信号管理
always_comb begin
    datapath_addr = vpc_i[11:2];
    w_data = bus_resp_i.r_data;
    w_tag.valid = 1'b1;
    w_tag.dirty = 1'b0;
    w_tag.page_index = pa[31:12];

    for(int way_id = 0; way_id < WAY_CNT ; way_id += 1) begin
        data_we[way_id] = '0;
        tag_we[way_id] = '0;
    end
    if(ENABLE_PLRU) begin
        for(int index_id = 0; index_id < 256;index_id += 1) begin
            use_vec[index_id] = '0;
        end
    end
    if(fsm_state == STATE_NORM && fsm_state == fsm_state_next) begin // ONLY UPDATE ON HIT STATE
        if(ENABLE_PLRU) begin
            use_vec[va[11:4]] |= sel;
        end
        if(stall) begin
            datapath_addr = va_early[11:2];
        end
    end else if(fsm_state == STATE_INVA) begin
        if(cache_op_type == 2'b00) begin
            // STORE TAG
            datapath_addr = va[11:2];
            w_tag = '0;
            tag_we[va[$clog2(WAY_CNT) - 1 : 0]] = 1'b1;
        end else if(cache_op_type == 2'b01) begin
            // INDEX INVALIDATE
            datapath_addr = va[11:2];
            w_tag.valid = '0;
            tag_we[va[$clog2(WAY_CNT) - 1 : 0]] = 1'b1;
        end else begin
            // HIT INVALIDATE
            datapath_addr = va[11:2];
            w_tag.valid = '0;
            tag_we |= sel;
        end
    end else if(fsm_state == STATE_FETC) begin
        datapath_addr = {va[11:4],fetch_cnt[1:0]};
        if(ENABLE_PLRU) begin
            data_we |= sel_vec[va[11:4]] & {WAY_CNT{bus_resp_i.data_ok}};
            tag_we  |= sel_vec[va[11:4]] /*& bus_resp_i.data_last & bus_resp_i.data_ok TODO: JUDGE WHETHER WE NEED THIS*/;
        end else begin
            data_we[lfsr_sel_vec] = 1'b1;
            tag_we[lfsr_sel_vec]  = 1'b1;
        end
    end else if(fsm_state == STATE_SYNC || fsm_state == STATE_SYN2) begin
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
    if(fsm_state == STATE_SYN2) begin
        fetched <= 1'b1;
    end else if(~stall)begin
        fetched <= 1'b0;
    end
end

always_ff @(posedge clk) begin
    if(~rst_n) begin
        fsm_state <= STATE_NORM;
    end else begin
        fsm_state <= fsm_state_next;
    end
end

// MMU 接入 及 MMU 对应异常
assign mmu_req_vpc_o = va_early;

// TLB 相关的逻辑
// assign page_index_raw = va_early[31:12];
assign page_index_raw = mmu_resp_i.paddr[31:12];

// FETCH异常逻辑
assign fetch_excp_o.adef = fetch_excp_adef || (va[31] && (plv == 2'd3) && trans_en);
assign fetch_excp_o.tlbr = !mmu_resp.found && trans_en;
assign fetch_excp_o.pif = mmu_resp.found && !mmu_resp.v && trans_en;
assign fetch_excp_o.ppi = (plv > mmu_resp.plv) && trans_en && mmu_resp.v;
assign fetch_excp = |fetch_excp_o;
endmodule
