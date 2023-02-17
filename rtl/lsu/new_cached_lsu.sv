`include "common.svh"
`include "decoder.svh"
`include "lsu_types.svh"

/*--JSON--{"module_name":"lsu","module_ver":"3","module_type":"module"}--JSON--*/

module lsu #(
    parameter int WAY_CNT = 2,
    parameter bit ENABLE_PLRU = 1'b0,
    parameter int WB_FIFO_DEPTH = 16
) (
    input logic clk,
    input logic rst_n,
    input  bus_busy_i,
    output bus_busy_o,

    // 控制信号
	input decode_info_t  decode_info_i, // EX stage
	input logic request_valid_i, // EX stage
	
	// 流水线数据输入输出
	input logic[31:0] vaddr_i, // EX stage
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
    input uncached_i,

	// 握手信号
	output logic busy_o,
	input stall_i

);

    // 全局控制信号
    logic stall;
    logic delay_stall;

    typedef struct packed {
        logic valid;
        logic dirty;
        logic[19:0] ppn;
    } tag_t;

    // 数据通路
    logic [31:0]m1_vaddr;
    logic [11:2]ram_r_addr;
    logic [11:2]ram_w_addr;
    logic [3:0] ram_we_data,data_strobe;
    logic ram_we_tag;
    logic [WAY_CNT - 1 : 0] ram_we_mask;

    tag_t        ram_w_tag;
    logic [31:0] ram_w_data;

    tag_t [WAY_CNT - 1 : 0]       ram_r_tag;    // M1 级的tag, 暂停时候会保持更新
    logic [WAY_CNT - 1 : 0][31:0] ram_r_data;   // M1 级的数据, 暂停时候会保持更新
    logic [WAY_CNT - 1 : 0][31:0] ram_raw_data;


    for(genvar way_id = 0 ; way_id < WAY_CNT ; way_id += 1) begin
        logic [3:0][7:0] raw_r_data;
        logic [21:0]     raw_r_tag;
        dcache_datapath datapath(
            .clk(clk),
            .rst_n(rst_n),
            .data_we_i(ram_we_data & {4{ram_we_mask[way_id]}}),
            .tag_we_i(ram_we_tag & ram_we_mask[way_id]),
            .r_addr_i(ram_r_addr),
            .w_addr_i(ram_w_addr),
            .data_o(raw_r_data),
            .data_i(ram_w_data),

            .tag_o(raw_r_tag),
            .tag_i(ram_w_tag)
        );

        // 脏写回使用
        assign ram_raw_data[way_id] = raw_r_data;

        // 添加寄存器, 处理暂停的情况
        logic [3:0][7:0] m1_data,m1_reg_data;
        tag_t            m1_tag,m1_reg_tag;

        logic [3:0][7:0] m2_w_data,wb_w_data;
        tag_t            m2_w_tag,wb_w_tag;

        logic [11:2] m1_r_addr,m2_w_addr,wb_w_addr;
        logic [3:0]  m2_w_byteen,wb_w_byteen;
        logic        m2_tag_we,wb_tag_we;

        // 数据流水
        assign m1_r_addr   = m1_vaddr[11:2];
        assign m2_w_addr   = ram_w_addr;
        assign m2_w_byteen = ram_we_data & {4{ram_we_mask[way_id]}};
        assign m2_tag_we   = ram_we_tag & ram_we_mask[way_id];
        assign m2_w_tag    = ram_w_tag;
        assign m2_w_data   = ram_w_data;
        always_ff @(posedge clk) begin
            wb_w_addr   <= m2_w_addr;
            wb_w_byteen <= m2_w_byteen;
            wb_tag_we   <= m2_tag_we;
            wb_w_tag    <= m2_w_tag;
            wb_w_data   <= m2_w_data;
        end

        // stall处理
        always_ff @(posedge clk) begin
            m1_reg_data <= m1_data;
            m1_reg_tag  <= m1_tag;
        end

        // 前馈, 保证M2级产生的请求可以被正确的转发到EX,M1级
        // M2级别的写请求对EX,M1不可见, WB级别的请求对M1不可见, 故在M1对M2和WB级的请求进行转发, 优先级M2高于WB
        always_comb begin
            m1_tag = delay_stall ? m1_reg_tag : raw_r_tag;
            if(wb_tag_we && (wb_w_addr[11:4] == m1_r_addr[11:4])) begin
                m1_tag = wb_w_tag;
            end
            if(m2_tag_we && (m2_w_addr[11:4] == m1_r_addr[11:4])) begin
                m1_tag = m2_w_tag;
            end
        end
        for(genvar byte_id = 0; byte_id < 4 ; byte_id += 1) begin
            always_comb begin
                m1_data[byte_id] = delay_stall ? m1_reg_data[byte_id] : raw_r_data[byte_id];
                if(wb_w_byteen[byte_id] && (wb_w_addr == m1_r_addr)) begin
                    m1_data[byte_id] = wb_w_data[byte_id];
                end
                if(m2_w_byteen[byte_id] && (m2_w_addr == m1_r_addr)) begin
                    m1_data[byte_id] = m2_w_data[byte_id];
                end
            end
        end
        assign ram_r_data[way_id] = m1_data;
        assign ram_r_tag[way_id]  = m1_tag;
    end

    // 第二阶段数据, 根据第二阶段数据构建状态机
    // 地址
    logic [31:0] paddr,vaddr;

    // 缓存状态
    tag_t [WAY_CNT - 1 : 0] tag;
    logic [WAY_CNT - 1 : 0][31:0] data;

    logic [$clog2(WAY_CNT) - 1 : 0] direct_sel_index;
    tag_t direct_sel_tag;
    tag_t sel_tag;
    logic [31:0] sel_data;

    // 比较信息
    logic [WAY_CNT - 1 : 0] match;
    logic [$clog2(WAY_CNT) - 1 : 0] match_index;
    logic miss;

    // 控制信息, 顺序编码
    logic [2:0] m1_ctrl,ctrl, m1_req_type,req_type;
    logic [1:0] m1_size,size;
    logic finish;
    logic bus_busy;
    localparam logic[2:0] C_NONE       = 3'd0;
    localparam logic[2:0] C_READ       = 3'd1;
    localparam logic[2:0] C_WRITE      = 3'd2;
    localparam logic[2:0] C_HIT_WB     = 3'd3;
    localparam logic[2:0] C_INVALID    = 3'd4;
    localparam logic[2:0] C_INVALID_WB = 3'd5;

    // 控制信息, 伪随机数
    logic [$clog2(WAY_CNT) - 1 : 0] next_sel;
    logic [WAY_CNT - 1 : 0]         next_sel_onehot;
    logic next_sel_taken;

    // 控制信息, 主状态机
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

    // 控制信息, FIFO写回状态机
    localparam logic[1:0] S_FEMPTY = 2'd0;
    localparam logic[1:0] S_FADR   = 2'd1;
    localparam logic[1:0] S_FDAT   = 2'd2;
    logic[1:0] fifo_fsm_state,fifo_fsm_next_state;
    logic fifo_full;
    always_ff @(posedge clk) begin
        if(~rst_n) fifo_fsm_state <= S_FEMPTY;
        else fifo_fsm_state <= fifo_fsm_next_state;
    end

    // 控制信息, CACHE行脏写回计数器, 三位, 最高位为结束位
    logic [2:0] wb_r_cnt,wb_delay_cnt,wb_w_cnt;
    logic [$clog2(WAY_CNT) - 1 : 0] wb_way_sel;
    logic [3:0][31:0] wb_fifo;
    logic [31:0] wb_sel_data;

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
        sel_tag = '0;
        sel_data = '0;
        match_index = '0;
        for(int i = 0 ; i < WAY_CNT ; i += 1) begin
            sel_tag  |= match[i] ? tag[i]  : '0;
            sel_data |= match[i] ? data[i] : '0;
            match_index = i[$clog2(WAY_CNT) - 1 : 0];
        end
    end

    // 主状态机
    always_comb begin
        fsm_state_next = fsm_state;
        case(fsm_state)
            S_NORMAL: begin
                // NORMAL下, 遇到需要处理的MISS或者缓存操作需要切换状态
                if((ctrl == C_READ || ctrl == C_WRITE) && !uncached && miss) begin
                    // CACHED READ | WRITE MISS
                    if(bus_busy) begin
                        fsm_state_next = S_WAIT_BUS;
                    end else begin
                        // 若被选择的缓存行为脏,需要写回,否之直接读取新数据。
                        if(tag[next_sel].dirty) begin
                            fsm_state_next = S_WADR;
                        end else begin
                            fsm_state_next = S_RADR;
                        end
                    end
                end
                if((ctrl == C_READ) && uncached && !finish) begin
                    // UNCACHED READ
                    if(bus_busy) begin
                        fsm_state_next = S_WAIT_BUS;
                    end else begin
                        fsm_state_next = S_PRADR;
                    end
                end
                if((ctrl == C_WRITE) && uncached && fifo_full) begin
                    // UNCACHED WRITE && FIFO FULL
                    fsm_state_next = S_WAIT_FULL;
                end
                if((((ctrl == C_INVALID_WB) && direct_sel_tag.valid  && direct_sel_tag.dirty) ||
                    ((ctrl == C_HIT_WB) && !miss/* && sel_tag.valid*/&&        sel_tag.dirty)) && !finish) begin
                    // CACOP WB 请求的CACHE行为脏, 需要写回
                    if(bus_busy) begin
                        fsm_state_next = S_WAIT_BUS;
                    end else begin
                        fsm_state_next = S_WADR;
                    end
                end
                // 最高优先级, 当前请求被无效化时, 不可暂停
                if(request_clr_hint_m2_i) begin
                    fsm_state_next = fsm_state;
                end
            end
            S_WAIT_BUS: begin
                // WAIT_BUS 需要等待让出总线后继续后面的操作
                if(~bus_busy) begin
                    fsm_state_next = S_NORMAL;
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
            S_WADR: begin
                // 写地址得到总线响应后继续后面的操作
                if(bus_resp_i.ready) begin
                    fsm_state_next = S_WDAT;
                end
            end
            S_WDAT: begin
                // 最后一个写数据得到总线响应后开始后续操作
                if(bus_resp_i.data_ok && bus_req_o.data_last) begin
                    // 区别INVALIDATE情况和MISS REFETCH情况
                    if(ctrl == C_READ || ctrl == C_WRITE) fsm_state_next = S_RADR;
                    else fsm_state_next = S_NORMAL;
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
                if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
                    fsm_state_next = S_NORMAL;
                end
            end
            S_WAIT_FULL: begin
                // FIFO不为空时候跳出此状态
                if(!fifo_full) begin
                    fsm_state_next = S_NORMAL;
                end
            end
        endcase
    end

    // 第二阶段 tag data 维护
    // 对于UNCACHED 的读请求, 将读取到的数据写入data寄存器, 并修改tag寄存器, 使其输出上可减少一个mux位
    always_ff @(posedge clk) begin
        if(~stall) begin
            tag  <= ram_r_tag;
            data <= ram_r_data;
        end else begin
            for(integer i = 0; i < WAY_CNT ; i += 1) begin
                if(i == 0 && (ram_we_mask[i] || uncached) && ram_we_tag) begin
                    tag[i] <= ram_w_tag;
                end else if(i != 0 && ram_we_mask[i] && !uncached && ram_we_tag) begin
                    tag[i] <= ram_w_tag;
                end else if(i != 0 && !ram_we_mask[i] && uncached && ram_we_tag) begin
                    tag[i].valid <= '0; // 无效化缓存行避免错误的hit
                end
                if((ram_we_mask[i] || (i == 0 && uncached)) && ram_we_data[0] && ram_w_addr[3:2] == paddr[3:2]) begin
                    data[i][ 7: 0] <= ram_w_data[ 7: 0];
                end
                if((ram_we_mask[i] || (i == 0 && uncached)) && ram_we_data[1] && ram_w_addr[3:2] == paddr[3:2]) begin
                    data[i][15: 8] <= ram_w_data[15: 8];
                end
                if((ram_we_mask[i] || (i == 0 && uncached)) && ram_we_data[2] && ram_w_addr[3:2] == paddr[3:2]) begin
                    data[i][23:16] <= ram_w_data[23:16];
                end
                if((ram_we_mask[i] || (i == 0 && uncached)) && ram_we_data[3] && ram_w_addr[3:2] == paddr[3:2]) begin
                    data[i][31:24] <= ram_w_data[31:24];
                end
            end
        end
    end

    // 地址通路
    always_ff @(posedge clk) begin
        if(~stall) begin
            m1_vaddr <= vaddr_i;
            vaddr <= m1_vaddr;
            paddr <= paddr_i;
        end
    end
    assign direct_sel_index = vaddr[$clog2(WAY_CNT) - 1 : 0];
    assign direct_sel_tag = tag[direct_sel_index];

    // 控制通路 : m1_ctrl ctrl m1_size size
    always_ff @(posedge clk) begin
        if(~rst_n || request_clr_m1_i || request_clr_m2_i) begin
            m1_ctrl <= C_NONE;
            ctrl    <= C_NONE;
            m1_size <= 2'b00;
            size    <= 2'b00;
        end else if(~stall) begin
            m1_req_type <= decode_info_i.m1.mem_type;
            req_type    <= m1_req_type;
            ctrl        <= m1_ctrl;
            size        <= m1_size;
            if(request_valid_i) begin
                if(decode_info_i.m1.mem_valid) begin
                    if(decode_info_i.m1.mem_write) begin
                        m1_ctrl <= C_WRITE;
                    end else begin
                        m1_ctrl <= C_READ;
                    end
                end else if(decode_info_i.m2.cacop && decode_info_i.general.inst25_0[2:0] == 3'd1) begin
                    // CACOP
                    if(decode_info_i.general.inst25_0[4:3] == 2'b00) begin
                        // store tag
                        m1_ctrl <= C_INVALID;
                    end else if(decode_info_i.general.inst25_0[4:3] == 2'b01) begin
                        // invalid_wb
                        m1_ctrl <= C_INVALID_WB;
                    end else begin
                        // hit invalidate
                        m1_ctrl <= C_HIT_WB;
                    end
                end else begin
                    m1_ctrl <= C_NONE;
                end
                case(decode_info_i.m1.mem_type[1:0])
                    `_MEM_TYPE_WORD: begin
                        m1_size <= 2'b10;
                    end
                    `_MEM_TYPE_HALF: begin
                        m1_size <= 2'b01;
                    end
                    `_MEM_TYPE_BYTE: begin
                        m1_size <= 2'b00;
                    end
                    default: begin
                        m1_size <= 2'b00;
                    end
                endcase
            end else begin
                m1_ctrl <= C_NONE; 
            end
        end
    end

    // 暂停信号
    assign stall = stall_i;
    assign busy_o = fsm_state != S_NORMAL || fsm_state_next != S_NORMAL;
    always_ff @(posedge clk) begin
        delay_stall <= stall;
    end

    // BUS忙信号
    assign bus_busy   = bus_busy_i || (fifo_fsm_state != S_FEMPTY);
    assign bus_busy_o = busy_o || (fifo_fsm_state != S_FEMPTY);

    // ram_r_addr 信号控制
    always_comb begin
        // 正常状态时, 直接从ex级别获得地址进行访问
        ram_r_addr = vaddr_i[11:2];
        // 需要WB时, 按照计数器读取cache行
        if(fsm_state == S_WADR || fsm_state == S_WDAT) begin
            ram_r_addr = {paddr[11:4], wb_r_cnt[1:0]};
        end
    end

    // wb_cnt 控制逻辑
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            wb_r_cnt <= 3'b100;
        end else begin
            if(fsm_state != S_WADR && fsm_state_next == S_WADR) begin
                wb_r_cnt <= 3'b000;
            end else if(!wb_r_cnt[2]) begin
                wb_r_cnt <= wb_r_cnt + 3'd1;
            end
        end
    end
    always_ff @(posedge clk) begin
        wb_delay_cnt <= wb_r_cnt;
    end
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            wb_w_cnt <= 3'b100;
        end else begin
            if(fsm_state != S_WDAT && fsm_state_next == S_WDAT) begin
                wb_w_cnt <= 3'b000;
            end else if(!wb_w_cnt[2] && bus_resp_i.data_ok) begin
                // 确保此时必然处于 S_WDAT 状态中
                wb_w_cnt <= wb_w_cnt + 3'd1;
            end
        end
    end

    // wb_fifo 逻辑
    always_ff @(posedge clk) begin
        if(~wb_delay_cnt[2]) begin
            wb_fifo[wb_delay_cnt[1:0]] <= ram_raw_data[wb_way_sel];
        end
    end

    // wb_sel_data 逻辑, 带透传的fifo
    assign wb_sel_data = (wb_delay_cnt[1:0] == wb_w_cnt[1:0]) ? ram_raw_data[wb_way_sel] : wb_fifo[wb_w_cnt];

    // wb_way_sel 逻辑
    always_comb begin
        wb_way_sel = '0;
        if(ctrl == C_INVALID_WB) begin
            wb_way_sel = direct_sel_index;
        end else if(ctrl == C_HIT_WB) begin
            wb_way_sel = match_index;
        end else begin
            wb_way_sel = next_sel;
        end
    end

    // refill_cnt 逻辑, 两位循环计数器
    always_ff @(posedge clk) begin
        if(fsm_state != S_RDAT && fsm_state_next == S_RDAT) begin
            refill_cnt <= 2'b00;
        end else begin
            if(bus_resp_i.data_ok) begin
                refill_cnt <= refill_cnt + 2'd1;
            end
        end
    end

    // ram_w_addr 逻辑
    always_comb begin
        // 正常状态时响应在M2级的写请求
        ram_w_addr = paddr[11:2];
        if(fsm_state == S_RDAT) begin
            // 当发生refill时, 从refill_cnt获得当前refill的offset
            ram_w_addr = {paddr[11:4], refill_cnt};
        end
    end

    // data_strobe 逻辑
    always_comb begin
        data_strobe = 4'b0000;
        case(size)
            2'b10:   data_strobe = 4'b1111; // WORD
            2'b01:   data_strobe = 4'b0011 << {paddr_o[1],1'b0};
            2'b00:   data_strobe = 4'b0001 <<  paddr_o[1:0];
            default: data_strobe = 4'b0000; // IMPOSIBLE
        endcase
    end

    // ram_we_data 逻辑
    always_comb begin
        // 正常状态时, 响应在M2级的写请求
        ram_we_data = 4'b0000;
        if(fsm_state == S_NORMAL && ctrl == C_WRITE && !request_clr_m2_i) begin
            ram_we_data = data_strobe;
        end else if(fsm_state == S_RDAT) begin
            // REFILL 状态, 全写
            ram_we_data = 4'b1111;
        end else if(fsm_state == S_PRDAT) begin
            // 特别的, 对于 UNCACHED 的读请求, 直接打开ram_we_data, 将第二阶段的数据寄存器直接作为结果寄存器使用
            ram_we_data = 4'b1111;
        end
    end

    // ram_w_data 逻辑
    always_comb begin
        ram_w_data = w_data_i << {paddr_o[1:0],3'b000};
        if(fsm_state == S_NORMAL) begin
            // 正常情况下, 可以直接使用 w_data_o 作为带写入的信息
            ram_w_data = w_data_i << {paddr_o[1:0],3'b000};
        end else begin
            // 在REFILL过程中, 写数据直接来自总线
            ram_w_data = bus_resp_i.r_data;
        end
    end

    // w_data_o 逻辑
    assign w_data_o = ram_w_data & {{8{ram_we_data[3]}},{8{ram_we_data[2]}},{8{ram_we_data[1]}},{8{ram_we_data[0]}}};

    // ram_we_tag 逻辑 TODO: check
    always_comb begin 
        // 正常情况时, 在M2级的写请求会触发一次脏写请求, 对于直接无效CACHE行的操作也在此响应
        ram_we_tag = '0;
        if(fsm_state == S_NORMAL) begin
            if(((ctrl == C_WRITE && !uncached) || ctrl == C_INVALID ||
                (ctrl == C_HIT_WB    && !miss && sel_tag.valid && !sel_tag.dirty) ||
                (ctrl == C_INVALID_WB && direct_sel_tag.valid && !direct_sel_tag.dirty) && !request_clr_m2_i)) begin
                ram_we_tag = '1;
            end
        end
        // 保证在写回的过程中CACHE行信息保持不变
        // 在写回完成后, 更新CACHE行信息
        else if(fsm_state == S_WDAT && fsm_state_next != S_WDAT && ctrl != C_READ && ctrl != C_WRITE) begin
            ram_we_tag = '1;
        end
        else if(fsm_state == S_RDAT) begin
            ram_we_tag = '1;
        end
        // 特殊的, 在uncached的读请求完成的时候, 使用ram_we_tag更新寄存器中的地址, 以完成一次UNCACHE读操作
        else if(fsm_state == S_PRDAT && fsm_state_next != S_PRDAT) begin
            ram_we_tag = '1;
        end
    end

    // ram_w_tag 逻辑 TODO: check
    always_comb begin
        // 正常情况时, 检查是WRITE 或是 INVALIDATE CACOP
        ram_w_tag.valid = 1'b1;
        ram_w_tag.dirty = 1'b1;
        ram_w_tag.ppn   = paddr[31:12];
        if(fsm_state == S_NORMAL) begin
            if(ctrl == C_INVALID || ctrl == C_HIT_WB || ctrl == C_INVALID_WB) begin
                ram_w_tag.valid = 1'b0;
                ram_w_tag.dirty = 1'b0;
            end
            // 对于写请求不需要特别处理
        end else if(fsm_state == S_WDAT) begin
            // HIT/INVALID_WB 的情况
            ram_w_tag.valid = 1'b0;
            ram_w_tag.dirty = 1'b0;
        end else if(fsm_state == S_RDAT) begin
            ram_w_tag.dirty = 1'b0;
        end
    end

    // ram_we_mask; // TODO : check
    always_comb begin
        ram_we_mask = '0;
        if(fsm_state == S_NORMAL) begin
            // 只在 (HIT & WRITE & !UNCACHED)| (VALID !DIRTY INVALID_WB) | (HIT VALID !DIRTY HIT_WB) 的情况下需要写,
            // 对于第一种情况和第三种情况, 写MASK为MATCH
            // 对于第二种情况, 进行直接索引
            if(!miss) begin
                if((ctrl == C_WRITE  && !uncached) ||
                   (ctrl == C_HIT_WB/* && sel_tag.valid*/ && !sel_tag.dirty && !request_clr_m2_i)) begin
                    ram_we_mask = match;
                end
            end
            if(ctrl == C_INVALID_WB) begin
                if(direct_sel_tag.valid && !direct_sel_tag.dirty) begin
                    ram_we_mask[direct_sel_index] = 1'b1;
                end
            end
        end
        else if(fsm_state == S_RDAT) begin
            // REFILL使用 新选择的way
            ram_we_mask = next_sel_onehot;
        end
        else if(fsm_state == S_WDAT) begin
            // 存在两类情况
            // 对于 READ | WRITE | HIT_WB 需要处理更新的是命中的行
            // 对于 INVALID_WB 需要处理的是选中的行
            if(ctrl == C_INVALID_WB) begin
                ram_we_mask[direct_sel_index] = 1'b1;
            end else begin
                ram_we_mask = match;
            end
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
        assign use_vec = match & {WAY_CNT{(fsm_state == S_NORMAL) && (ctrl == C_READ || ctrl == C_WRITE) && (!uncached)}};
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
        if(fsm_state == S_WDAT || fsm_state == S_PRDAT) begin
            finish <= 1'b1;
        end else if(~stall) begin
            finish <= 1'b0;
        end
    end

    // 写回 FIFO 状态机
    typedef struct packed {
        logic [31:0] addr;
        logic [31:0] data;
        logic [ 3:0] strobe;
        logic [ 1:0] size;
    } pw_fifo_t;
    pw_fifo_t [WB_FIFO_DEPTH - 1 : 0] pw_fifo;
    pw_fifo_t pw_req,pw_handling;
    logic pw_w_e,pw_r_e,pw_empty;
    logic[$clog2(WB_FIFO_DEPTH) : 0] pw_w_ptr,pw_r_ptr,pw_cnt;
    assign pw_cnt = pw_w_ptr - pw_r_ptr;
    assign pw_empty = pw_cnt == '0;
    assign fifo_full = pw_cnt[$clog2(WB_FIFO_DEPTH)];
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            pw_w_ptr <= '0;
        end else if(pw_w_e && !(pw_empty && pw_r_e)) begin
            pw_w_ptr <= pw_w_ptr + 1'd1;
        end
    end
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            pw_r_ptr <= '0;
        end else if(pw_r_e && !pw_empty) begin
            pw_r_ptr <= pw_r_ptr + 1'd1;
        end
    end
    always_ff @(posedge clk) begin
        if(pw_r_e) begin
            if(!pw_empty) pw_handling <= pw_fifo[pw_r_ptr[$clog2(WB_FIFO_DEPTH) - 1: 0]];
            else          pw_handling <= pw_req;
        end
    end
    always_ff @(posedge clk) begin
        if(pw_w_e) begin
            pw_fifo[pw_w_ptr[$clog2(WB_FIFO_DEPTH) - 1: 0]] <= pw_req;
        end
    end
    always_comb begin
        pw_req.addr   = paddr;
        pw_req.data   = w_data_i << {paddr_o[1:0],3'b000};
        pw_req.strobe = data_strobe;
        pw_req.size   = size;
    end
    always_comb begin
        fifo_fsm_next_state = fifo_fsm_state;
        case(fifo_fsm_state)
            S_FEMPTY: begin
                if(pw_w_e) begin
                    fifo_fsm_next_state = S_FADR;
                end
            end
            S_FADR: begin
                if(bus_resp_i.ready) begin
                    fifo_fsm_next_state = S_FDAT;
                end
            end
            S_FDAT: begin
                if(bus_resp_i.data_ok) begin
                    if(pw_empty && !pw_w_e) begin
                        // 没有后续请求
                        fifo_fsm_next_state = S_FEMPTY;
                    end else begin
                        // 有后续请求
                        fifo_fsm_next_state = S_FADR;
                    end
                end
            end
        endcase
    end
    always_ff @(posedge clk) begin
        fifo_fsm_state <= fifo_fsm_next_state;
    end

    // W-R使能
    // pw_r_e pw_w_e
    assign pw_r_e = (fifo_fsm_state == S_FDAT && fifo_fsm_next_state == S_FADR) || (fifo_fsm_state == S_FEMPTY && fifo_fsm_next_state == S_FADR);
    assign pw_w_e = !stall && uncached && (ctrl == C_WRITE) && !request_clr_m2_i;

    always_ff @(posedge clk) begin
        if(~stall) begin
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
        bus_req_o.addr        = paddr;

        bus_req_o.data_ok     = 1'b0;
        bus_req_o.data_last   = 1'b0;
        bus_req_o.data_strobe = 4'b1111;
        bus_req_o.w_data      = wb_sel_data;
        // 优先级最高的是UNCACHED FIFO
        if(fifo_fsm_state != S_FEMPTY) begin
            if(fifo_fsm_state == S_FADR) begin
                bus_req_o.valid      = 1'b1;
                bus_req_o.write      = 1'b1;
                bus_req_o.burst_size = 4'b0000;
                bus_req_o.data_size  = pw_handling.size;
                bus_req_o.addr       = pw_handling.addr;
            end else begin
                // S_FDAT
                bus_req_o.data_ok     = 1'b1;
                bus_req_o.data_last   = 1'b1;
                bus_req_o.data_strobe = pw_handling.strobe;
                bus_req_o.w_data      = pw_handling.data;
            end
        end else if(fsm_state == S_RADR) begin
            // REFILL 的请求
            bus_req_o.valid      = 1'b1;
            bus_req_o.addr       = {paddr[31:4],4'd0};
        end else if(fsm_state == S_RDAT) begin
            bus_req_o.data_ok    = 1'b1;
        end else if(fsm_state == S_WADR) begin
            // 写回的请求
            bus_req_o.valid      = 1'b1;
            bus_req_o.write      = 1'b1;
            bus_req_o.addr       = {tag[next_sel].ppn,paddr[11:4],4'd0};
        end else if(fsm_state == S_WDAT) begin
            bus_req_o.data_ok    = 1'b1;
            bus_req_o.data_last  = (wb_w_cnt == 3'b011);
        end else if(fsm_state == S_PRADR) begin
            bus_req_o.valid      = 1'b1;
            bus_req_o.burst_size = 4'b0000;
            bus_req_o.data_size  = size;
        end else if(fsm_state == S_PRDAT) begin
            bus_req_o.data_ok    = 1'b1;
        end
    end

    assign vaddr_o = vaddr;
    assign paddr_o = paddr;
    // 输出处理逻辑
	always_comb begin
		case(req_type[1:0])
			`_MEM_TYPE_WORD: begin
				r_data_o = sel_data;
			end
			`_MEM_TYPE_HALF: begin
				if(paddr_o[1])
					r_data_o = {{16{(sel_data[31] & ~req_type[2])}},sel_data[31:16]};
				else
					r_data_o = {{16{(sel_data[15] & ~req_type[2])}},sel_data[15:0]};
			end
			`_MEM_TYPE_BYTE: begin
				if(paddr_o[1])
					if(paddr_o[0])
						r_data_o = {{24{(sel_data[31] & ~req_type[2])}},sel_data[31:24]};
					else
						r_data_o = {{24{(sel_data[23] & ~req_type[2])}},sel_data[23:16]};
				else
					if(paddr_o[0])
						r_data_o = {{24{(sel_data[15] & ~req_type[2])}},sel_data[15:8]};
					else
						r_data_o = {{24{(sel_data[7 ] & ~req_type[2])}},sel_data[7 :0]};
			end
			default: begin
				r_data_o = sel_data;
			end
		endcase
	end

endmodule
