`include "common.svh"
`include "decoder.svh"
`include "lsu_types.svh"

/*--JSON--{"module_name":"lsu","module_ver":"3","module_type":"module"}--JSON--*/

module lsu #(
    parameter int WAY_CNT = 2,
    parameter bit ENABLE_PLRU = 1'b0
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
    logic [11:2]ram_waddr;               // TODO
    logic [3:0] ram_we_data;             // TODO 写数据位使能
    logic ram_we_tag;                    // TODO 写tag使能
    logic [WAY_CNT - 1 : 0] ram_we_mask; // TODO 写使能mask

    tag_t        ram_w_tag;              // TODO 待写入的tag
    logic [31:0] ram_w_data;             // TODO 待写入的data

    tag_t [WAY_CNT - 1 : 0]       ram_r_tag;    // M1 级的tag，暂停时候会保持更新
    logic [WAY_CNT - 1 : 0][31:0] ram_r_data;   // M1 级的数据，暂停时候会保持更新
    logic [WAY_CNT - 1 : 0][31:0] ram_raw_data;  // TODO WRITE BACK 使用的原始信号


    for(genvar way_id = 0 ; way_id < WAY_CNT ; way_id += 1) begin
        logic [3:0][7:0] raw_r_data;
        logic [21:0]     raw_rtag;
        dcache_datapath datapath(
            .clk(clk),
            .rst_n(rst_n),
            .data_we_i(ram_we_data & {4{ram_we_mask[way_id]}}),
            .tag_we_i(ram_we_tag & ram_we_mask[way_id]),
            .r_addr_i(ram_r_addr),
            .w_addr_i(ram_waddr),
            .data_o(raw_r_data),
            .data_i(ram_w_data),

            .tag_o(raw_rtag),
            .tag_i(ram_w_tag)
        );

        // 添加寄存器，处理暂停的情况
        logic [3:0][7:0] m1_reg_data;
        tag_t            m1_reg_tag;

        logic [3:0][7:0] m1_data,m2_data,wb_data;
        tag_t            m2_tag,wb_tag;

        logic [11:2] m1_r_addr,m2_w_addr,wb_w_addr;
        logic [3:0]  m2_w_byteen,wb_w_byteen;
        logic        m2_tag_we,wb_tag_we;

        // 数据流水
        // always_ff @(posedge clk) begin
        //     m1_r_addr <= ram_r_addr;
        // end
        assign m1_r_addr = m1_vaddr[11:2];
        assign m2_w_addr = ram_waddr;
        assign m2_w_byteen = ram_we_data & {4{ram_we_mask[way_id]}};
        assign m2_tag_we = ram_we_tag & ram_we_mask[way_id];
        always_ff @(posedge clk) begin
            wb_w_addr   <= m2_w_addr;
            wb_w_byteen <= m2_w_byteen;
            wb_tag_we   <= m2_tag_we;
        end

        // stall处理
        always_ff @(posedge clk) begin
            m1_reg_data <= m1_data;
            m1_reg_tag  <= ram_r_tag[way_id];
        end

        // 前馈，保证M2级产生的请求可以被正确的转发到EX,M1级
        // M2级别的写请求对EX,M1不可见，WB级别的请求对M1不可见，故在M1对M2和WB级的请求进行转发，优先级M2高于WB
        always_comb begin
            ram_r_tag[way_id] = delay_stall ? m1_reg_tag : raw_rtag;
            if(wb_tag_we && (wb_w_addr[11:4] == m1_r_addr[11:4])) begin
                ram_r_tag[way_id] = wb_tag;
            end
            if(m2_tag_we && (m2_w_addr[11:4] == m1_r_addr[11:4])) begin
                ram_r_tag[way_id] = m2_tag;
            end
        end
        for(genvar byte_id = 0; byte_id < 4 ; byte_id += 1) begin
            always_comb begin
                m1_data[byte_id] = delay_stall ? m1_reg_data[byte_id] : raw_r_data[byte_id];
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
    logic [31:0] paddr,vaddr;           // TODO 接线
    // 缓存状态
    tag_t [WAY_CNT - 1 : 0] tag;
    logic [WAY_CNT - 1 : 0][31:0] data;

    // 比较信息
    logic [WAY_CNT - 1 : 0] match;
    logic miss;

    // 控制信息, 顺序编码
    logic [2:0] m1_ctrl,ctrl; // TODO 控制信号
    logic [1:0] m1_size,size;
    logic finish;     // TODO 完成寄存器
    logic bus_busy;   // TODO 总线忙HINT
    localparam logic[2:0] C_NONE       = 3'd0;
    localparam logic[2:0] C_READ       = 3'd1;
    localparam logic[2:0] C_WRITE      = 3'd2;
    localparam logic[2:0] C_HITWB      = 3'd3;
    localparam logic[2:0] C_INVALID    = 3'd4;
    localparam logic[2:0] C_INVALID_WB = 3'd5;

    // 控制信息, 伪随机数
    logic [$clog2(WAY_CNT) - 1 : 0] next_sel;        // TODO 接线
    logic [WAY_CNT - 1 : 0]         next_sel_onehot; // TODO 接线
    logic random_taken;                              // TODO 接线

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

    // 控制信息，FIFO写回状态机
    localparam logic[1:0] S_FEMPTY = 2'd0;
    localparam logic[1:0] S_FADR   = 2'd1;
    localparam logic[1:0] S_FDAT   = 2'd2;
    logic[1:0] fifo_fsm_state,fifo_fsm_next_state; // TODO 接线
    logic fifo_full // TODO 接线
    always_ff @(posedge clk) begin
        if(~rst_n) fifo_fsm_state <= S_FEMPTY;
        else fifo_fsm_state <= fifo_fsm_next_state;
    end

    // 控制信息, CACHE行脏写回计数器, 三位, 最高位为结束位
    logic [2:0] wb_r_cnt,wb_delay_cnt,wb_w_cnt;
    logic [$clog2(WAY_CNT) - 1 : 0] wb_way_sel; // TODO
    logic [3:0][31:0] wb_fifo;
    logic [31:0] wb_sel_data;

    // cached 信息
    logic uncached; // TODO 接线

    // 生成比较信息
    for(genvar way_id = 0; way_id < WAY_CNT ; way_id += 1) begin
        assign match[way_id] = tag[way_id].valid && (tag[way_id].ppn == paddr[31:12]);
    end
    assign miss = ~(|match);

    // 主状态机
    always_comb begin
        fsm_state_next = fsm_state;
        case(fsm_state)
            S_NORMAL: begin
                // NORMAL下，遇到需要处理的MISS或者缓存操作需要切换状态
                if((ctrl == C_READ || ctrl == C_WRITE) && !finish && !uncached && miss) begin
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
                if((ctrl == C_READ) && !finish && uncached) begin
                    // UNCACHED READ
                    if(bus_busy) begin
                        fsm_state_next = S_WAIT_BUS;
                    end else begin
                        fsm_state_next = S_PRADR;
                    end
                end
                if((ctrl == C_WRITE) && !finish && uncached && fifo_full) begin
                    // UNCACHED WRITE && FIFO FULL
                    fsm_state_next = S_WAIT_FULL;
                end
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
                if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
                    // 区别INVALIDATE情况和MISS REFETCH情况
                    if(ctrl == C_READ || ctrl == C_WRITE) fsm_state_next = S_RADR;
                    else fsm_state_next = S_NORMAL;
                end
            end
            S_PRADR: begin
                // 读地址得到响应后继续后面的操作
                iif(bus_resp_i.ready) begin
                    fsm_state_next = S_NORMAL;
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
    // 对于UNCACHED 的读请求，将读取到的数据写入data寄存器，并修改tag寄存器，使其输出上可减少一个mux位
    always_ff @(posedge clk) begin
        if(~stall) begin
            tag  <= ram_r_tag;
            data <= ram_r_data;
        end else begin
            for(integer i = 0; i < WAY_CNT ; i += 1) begin
                if((ram_we_mask[i] || (i == 0 && uncached)) && ram_we_tag) begin
                    tag[i] <= ram_w_tag;
                end
                if((ram_we_mask[i] || (i == 0 && uncached)) && ram_we_data[0] && ram_waddr[3:2] == paddr[3:2]) begin
                    data[i][ 7: 0] <= ram_w_data[ 7: 0];
                end
                if((ram_we_mask[i] || (i == 0 && uncached)) && ram_we_data[1] && ram_waddr[3:2] == paddr[3:2]) begin
                    data[i][15: 8] <= ram_w_data[15: 8];
                end
                if((ram_we_mask[i] || (i == 0 && uncached)) && ram_we_data[2] && ram_waddr[3:2] == paddr[3:2]) begin
                    data[i][23:16] <= ram_w_data[23:16];
                end
                if((ram_we_mask[i] || (i == 0 && uncached)) && ram_we_data[3] && ram_waddr[3:2] == paddr[3:2]) begin
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

    // 控制通路 : m1_ctrl ctrl m1_size size
    always_ff @(posedge clk) begin
        if(~rst_n || request_clr_m1_i || request_clr_m2_i) begin
            m1_ctrl <= C_NONE;
            ctrl    <= C_NONE;
            m1_size <= 2'b00;
            size    <= 2'b00;
        end else if(~stall) begin
            ctrl    <= m1_ctrl;
            size    <= m1_size;
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
                        m1_ctrl <= C_HITWB;
                    end
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

    // ram_r_addr 信号控制
    always_comb begin
        // 正常状态时，直接从ex级别获得地址进行访问
        ram_r_addr = vaddr_i[11:2];
        // 需要WB时，按照计数器读取cache行
        if(fsm_state == S_WADR || fsm_state == S_WDAT) begin
            ram_r_addr = {paddr[11:4], wb_r_cnt[1:0]};
        end
    end

    // wb_cnt 控制逻辑
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            wb_r_cnt <= 3'b100;
        end else begin
            if(fsm_state_next == S_WADR) begin
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
            if(fsm_state_next == S_WDAT) begin
                wb_w_cnt <= 3'b000;
            end else if(!wb_w_cnt[2] && mmu_resp_i.data_ok) begin
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

    // wb_data 逻辑, 带透传的fifo
    assign wb_sel_data = (wb_delay_cnt[1:0] == wb_w_cnt[1:0]) ? ram_raw_data[wb_way_sel] : wb_fifo[wb_w_cnt];

endmodule
