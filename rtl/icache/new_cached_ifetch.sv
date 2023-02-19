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
    logic stall;
    logic delay_stall;

    // 异常控制信号
    mmu_s_resp_t mmu_resp;
    logic [1:0] plv;
    logic trans_en,trans_en_i;
    logic adef,tlbr,pif,ppi;
    logic excp_inv;

    // ATTACHED valid 掩码信息传递
    logic f1_valid_mask,valid_mask; 
    logic [ATTACHED_INFO_WIDTH - 1 : 0] f1_attached;
    always_ff @(posedge clk) begin
        if(!stall) begin
            f1_attached   <= attached_i ;
            attached_o    <= f1_attached;
            f1_valid_mask <= valid_i ;
            valid_mask    <= f1_valid_mask;
        end
    end
    

    typedef struct packed {
        logic valid;
        logic[19:0] ppn;
    } tag_t;

    // 数据通路
    logic [31:0] f1_vaddr;
    logic [11:2] ram_rw_addr;
    logic        ram_we_data,ram_we_tag;
    logic [WAY_CNT - 1 : 0] ram_we_mask;

    tag_t        ram_w_tag;
    logic [31:0] ram_w_data;

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
            // 对于UNCACHED 指令产生的效果, 需要后续指令立即可见
            if(f2_tag_we  && ( f2_w_addr[11:4] == f1_r_addr[11:4])) begin
                f1_tag = f2_w_tag;
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
    logic [31:0] paddr,vaddr;

    // 缓存状态
    tag_t [WAY_CNT - 1 : 0] tag;
    logic [WAY_CNT - 1 : 0][FETCH_SIZE - 1 : 0][31:0] data; 

    logic [$clog2(WAY_CNT) - 1 : 0] direct_sel_index;
    logic [FETCH_SIZE - 1 : 0][31:0] sel_data;

    // 比较信息
    logic [WAY_CNT - 1 : 0] match;
    logic [$clog2(WAY_CNT) - 1 : 0] match_index;
    logic miss;

    // 控制信息, 顺序编码
    logic [1:0] f1_ctrl,ctrl;
    logic finish;
    logic bus_busy;
    localparam logic[1:0] C_NONE    = 2'd0;
    localparam logic[1:0] C_FETC    = 2'd1;
    // 对于ICACHE来说, INVALID 和 STORE TAG 是完全等价的
    localparam logic[1:0] C_INVALID = 2'd2;
    localparam logic[1:0] C_HIT     = 2'd3;

    // 控制信息, 伪随机数
    logic [$clog2(WAY_CNT) - 1 : 0] next_sel;
    logic [WAY_CNT - 1 : 0]         next_sel_onehot;
    logic next_sel_taken;

    // 控制信息, 主状态机
    localparam logic[2:0] S_NORMAL    = 3'd0;
    localparam logic[2:0] S_WAIT_BUS  = 3'd1;
    localparam logic[2:0] S_RADR      = 3'd2;
    localparam logic[2:0] S_RDAT      = 3'd3;
    localparam logic[2:0] S_PRADR     = 3'd4;
    localparam logic[2:0] S_PRDAT     = 3'd5;
    logic[2:0] fsm_state,fsm_state_next;
    always_ff @(posedge clk) begin
        if(~rst_n) fsm_state <= S_NORMAL;
        else fsm_state <= fsm_state_next;
    end

    // 控制信息, CACHE行REFILL计数器, 两位
    logic [1:0] refill_cnt;

    // cached 信息
    logic uncached;

    // 生成比较信息
    for(genvar way_id = 0; way_id < WAY_CNT ; way_id += 1) begin
        assign match[way_id] = tag[way_id].valid && (tag[way_id].ppn == paddr[31:12]);
    end
    assign miss = ~(|match);
    always_comb begin
        sel_data = data[0];
        match_index = '0;
        for(int i = 0 ; i < WAY_CNT ; i += 1) begin
            if(match[i]) begin
                sel_data    = data[i];
                match_index = i[$clog2(WAY_CNT) - 1 : 0];
            end
        end
    end

    // 主状态机
    always_comb begin
        fsm_state_next = fsm_state;
        case(fsm_state)
            S_NORMAL: begin
                // 在NORMAL状态下, 只需要处理REFILL 或者 UNCACHED 两种请求
                if(ctrl == C_FETC && !uncached && miss   && !clr_i && !excp_inv) begin
                    if(bus_busy) begin
                        fsm_state_next = S_WAIT_BUS;
                    end else begin
                        fsm_state_next = S_RADR;
                    end
                end
                if(ctrl == C_FETC && uncached && !finish && !clr_i && !excp_inv) begin
                    if(bus_busy) begin
                        fsm_state_next = S_WAIT_BUS;
                    end else begin
                        fsm_state_next = S_PRADR;
                    end
                end
            end
            S_WAIT_BUS: begin
                // WAIT_BUS 需要等待让出总线后继续后面的操作
                if(!bus_busy) begin
                    if(uncached) begin
                        fsm_state_next = S_PRADR;
                    end else begin
                        fsm_state_next = S_RADR;
                    end
                end
            end
            S_RADR: begin
                // 读地址得到响应后继续后面的操作
                if(bus_resp_i.ready) begin
                    fsm_state_next = S_RDAT;
                end
            end
            S_RDAT: begin
                // 读数据拿到最后一个数据后开始后续操作
                if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
                    fsm_state_next = S_NORMAL;
                end
            end
            S_PRADR: begin
                // 读地址得到响应后继续后面的操作
                if(bus_resp_i.ready) begin
                    fsm_state_next = S_PRDAT;
                end
            end
            S_PRDAT: begin
                // 读数据得到响应后继续后面的操作
                if(bus_resp_i.data_ok && bus_resp_i.data_last &&  refill_cnt[0]) begin
                    fsm_state_next = S_NORMAL;
                end else 
                if(bus_resp_i.data_ok && bus_resp_i.data_last && !refill_cnt[0]) begin
                    fsm_state_next = S_PRADR;
                end
            end
        endcase
    end

    // 第二阶段的 tag data 维护
    // 对于UNCACHED 的读请求, 将读取到的数据写入第一路的data寄存器, 使得最终输出只由一个寄存器 + 2-1 MUX 组成
    always_ff @(posedge clk) begin
        if(!stall) begin
            tag  <= ram_r_tag;
            data <= ram_r_data;
        end else begin
            for(integer i = 0 ; i < WAY_CNT ; i += 1) begin
                if(i == 0  && (ram_we_mask[i] || uncached) && ram_we_tag) begin
                    tag[i] <= ram_w_tag;
                end else if(i != 0 && ram_we_mask[i] && !uncached && ram_we_tag) begin
                    tag[i] <= ram_w_tag;
                end else if(i != 0 && !ram_we_mask[i] && uncached && ram_we_tag) begin
                    tag[i].valid <= '0;
                end
                if((ram_we_mask[i] || (i == 0 && uncached)) && ram_we_data && ram_w_addr[3:2 + $clog2(FETCH_SIZE)] == paddr[3:2 + $clog2(FETCH_SIZE)]) begin
                    if(FETCH_SIZE == 1) begin
                        data[i] <= ram_w_data;
                    end else begin
                        data[i][2 + $clog2(FETCH_SIZE) - 1 : 2] <= ram_w_data;
                    end
                end
            end
        end
    end

    // 地址通路
    always_ff @(posedge clk) begin
        if(!stall) begin
            f1_vaddr <= vpc_i;
            vaddr    <= f1_vaddr;
            paddr    <= mmu_resp_i.paddr;
        end
    end
    assign direct_sel_index = vaddr[$clog2(WAY_CNT) - 1 : 0];

    // 控制通路 f1_ctrl ctrl
    always_ff @(posedge clk) begin
        if(~rst_n || clr_i) begin
            f1_ctrl <= C_NONE;
            ctrl    <= C_NONE;
        end else if (~stall) begin
            ctrl <= f1_ctrl;
            if(cacheop_valid_i) begin
                // 强制优先接受CACHEOP的请求
                if(cacheop_i == 2'b10) begin
                    f1_ctrl <= C_HIT;
                end else begin
                    f1_ctrl <= C_INVALID;
                end
            end else if(|valid_i) begin
                f1_ctrl <= C_FETC;
            end else begin
                f1_ctrl <= C_NONE;
            end
        end
    end

    // 暂停信号
    logic fsm_busy;
    assign fsm_busy = (fsm_state != S_NORMAL) || (fsm_state_next != S_NORMAL);
    assign stall = !ready_i || fsm_busy;
    assign ready_o = !stall && !cacheop_valid_i;
    assign cacheop_ready_o = !stall;
    always_ff @(posedge clk) begin
        delay_stall <= stall;
    end

    // BUS 忙信号
    assign bus_busy = bus_busy_i;

    // ram_rw_addr 信号控制
    always_comb begin
        // 正常状态时, 从VPC级别获得地址进行sram访问
        ram_rw_addr = vpc_i[11:2];
        if(fsm_state == S_RDAT) begin
            // REFILL状态, 从refill_cnt获得写地址
            ram_rw_addr = {paddr[11:4], refill_cnt};
        end else if(fsm_state == S_PRDAT) begin
            // 读透传模式, 保证总线的数据可以写入输出用的data寄存器
            ram_rw_addr = paddr[11:2];
        end
    end

    // refill_cnt 逻辑, 两位循环计数器
    always_ff @(posedge clk) begin
        if((fsm_state == S_NORMAL && fsm_state_next == S_RADR ) ||
           (fsm_state == S_NORMAL && fsm_state_next == S_PRADR)) begin
            refill_cnt <= 2'b00;
        end else begin
            if(bus_resp_i.data_ok && (fsm_state == S_RDAT || (fsm_state == S_PRDAT && bus_resp_i.data_last))) begin
                refill_cnt <= refill_cnt + 2'd1;
            end
        end
    end

    // ram_we_data 逻辑
    always_comb begin
        // 正常状态时, 没有任何写需求
        ram_we_data ='0;
        if(fsm_state == S_RDAT) begin
            // REFILL 状态, 写
            ram_we_data = '1;
        end else if(fsm_state == S_PRDAT) begin
            // 特别的, 对于 UNCACHED 的读请求, 直接打开ram_we_data, 将第二阶段的数据寄存器直接作为结果寄存器使用
            ram_we_data = '1;
        end
    end

    // ram_w_data 逻辑
    assign ram_w_data = bus_resp_i.r_data;

    // ram_we_tag 逻辑
    always_comb begin
        // 在F2的请求, 若为CACHE指令, 则需要无效化对应的CACHE行进行写操作
        ram_we_tag = '0;
        if(fsm_state == S_NORMAL && (ctrl == C_INVALID || ctrl == C_HIT) && !clr_i && !excp_inv) begin
            ram_we_tag = '1;
        end else if(fsm_state == S_RDAT)  begin
            // refill 时 更新tag
            ram_we_tag = '1;
        end else if(fsm_state == S_PRDAT) begin
            // 特殊的, 在uncached的读请求完成的时候, 使用ram_we_tag更新寄存器中的地址, 以完成一次UNCACHE读操作
            ram_we_tag = '1;
        end
    end

    // ram_w_tag 逻辑 TODO: check
    always_comb begin
        // 正常情况时, 检查是否是 INVALIDATE CACOP 或者 REFILL
        ram_w_tag.valid = 1'b1;
        ram_w_tag.ppn   = paddr[31:12];
        if(fsm_state == S_NORMAL) begin
            if(ctrl == C_INVALID || ctrl == C_HIT) begin
                ram_w_tag.valid = 1'b0;
            end
        end
    end

    // ram_we_mask 逻辑 // TODO : check
    always_comb begin
        ram_we_mask = '0;
        if(fsm_state == S_NORMAL) begin
            // 只在INVALIDATE 的时候需要写
            if(ctrl == C_INVALID) begin
                ram_we_mask[direct_sel_index] = 1'b1;
            end else if(ctrl == C_HIT) begin
                ram_we_mask = match;
            end
        end
        else if(fsm_state == S_RDAT) begin
            ram_we_mask = next_sel_onehot;
        end
    end

    // next_sel_taken 在REFILL 的最后一个阶段
    assign next_sel_taken = fsm_state == S_RDAT && fsm_state_next != S_RDAT;

    // 生成下一个WAY SELECTION
    if(!ENABLE_PLRU) begin
        lfsr #(
            .LfsrWidth((8 * $clog2(WAY_CNT)) >= 64 ? 64 : (8 * $clog2(WAY_CNT))),
            .OutWidth($clog2(WAY_CNT))
        ) lfsr (
            .clk(clk),
            .rst_n(rst_n),
            .en_i(next_sel_taken),
            .out_o(next_sel)
        );
        always_comb begin
            next_sel_onehot = '0;
            next_sel_onehot[next_sel] = 1'b1;
        end
    end else begin
        // PLRU
        logic[WAY_CNT - 1 : 0] use_vec;
        logic[255:0][WAY_CNT - 1 : 0] sel_vec;
        for(genvar cache_index = 0; cache_index < 256; cache_index += 1) begin : cache_line
            plru_tree #(
                .ENTRIES(WAY_CNT)
            )plru(
                .clk(clk),
                .rst_n(rst_n),
                .used_i(paddr[11:4] == cache_index[7:0] ? use_vec : '0),
                .plru_o(sel_vec[cache_index])
            );
        end
        assign next_sel_onehot = sel_vec[paddr[11:4]];
        assign use_vec = match & {WAY_CNT{(fsm_state == S_NORMAL) && ctrl == C_FETC && !uncached}};
        always_comb begin
            next_sel = '0;
            for(integer i = 0; i < WAY_CNT ; i += 1) begin
                if(next_sel_onehot[i]) begin
                    next_sel = i[$clog2(WAY_CNT) - 1 : 0];
                end
            end
        end
    end

    // finish 寄存器管理
    always_ff @(posedge clk) begin
        if(fsm_state == S_PRDAT) begin
            finish <= 1'b1;
        end else if(~stall) begin
            finish <= 1'b0;
        end
    end

    // uncached 逻辑
    always_ff @(posedge clk) begin
        if(!stall) begin
            uncached <= uncached_i;
            // uncached <= '1;
        end
    end

    // BUS REQ 赋值
    always_comb begin
        bus_req_o.valid       = 1'b0;
        bus_req_o.write       = 1'b0;
        bus_req_o.burst_size  = 4'b0011;
        bus_req_o.cached      = 1'b0;
        bus_req_o.data_size   = 2'b10;
        bus_req_o.addr        = {paddr[31:2],2'b00};

        bus_req_o.data_ok     = 1'b0;
        bus_req_o.data_last   = 1'b0;
        bus_req_o.data_strobe = 4'b0000;
        bus_req_o.w_data      = '0;
        if(fsm_state == S_RADR) begin
            bus_req_o.valid = 1'b1;
            bus_req_o.addr  = {paddr[31:4],4'd0};
        end else if(fsm_state == S_RDAT || fsm_state == S_PRDAT) begin
            bus_req_o.data_ok    = 1'b1;
        end else if(fsm_state == S_PRADR) begin
            bus_req_o.valid      = 1'b1;
            bus_req_o.burst_size = 4'b0000;
        end
    end

    // 异常处理
    always_ff @(posedge clk) begin
        if(!stall) begin
            trans_en <= trans_en_i;
            mmu_resp <= mmu_resp_i;
        end
    end
    assign excp_inv = adef|tlbr|pif|ppi;
    assign adef =(vaddr[1:0] || (vaddr[31] && (plv == 2'd3) && trans_en)) && ctrl == C_FETC;
    assign tlbr = !mmu_resp.found && trans_en    && ctrl == C_FETC;
    assign pif  = mmu_resp.found  && !mmu_resp.v && trans_en && ctrl == C_FETC;
    assign ppi  = mmu_resp.found  && (plv > mmu_resp.plv) && trans_en && mmu_resp.v && ctrl == C_FETC;
    assign fetch_excp_o = '{
        adef: adef,
        tlbr: tlbr,
        pif : pif,
        ppi : ppi
    };

    // 输出逻辑
    assign vpc_o = vaddr;
    assign ppc_o = paddr;
    assign mmu_req_vpc_o = f1_vaddr;
    assign inst_o = sel_data;
    assign valid_o = valid_mask & {FETCH_SIZE{ctrl == C_FETC && !clr_i && !excp_inv}};

endmodule
