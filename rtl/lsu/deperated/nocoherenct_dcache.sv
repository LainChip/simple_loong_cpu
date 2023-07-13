/*--JSON--{"module_name":"lsu","module_ver":"10","module_type":"module"}--JSON--*/

module lsu #(
    parameter int CACHE_SHIFT = 12, // options from 12 - 14
    parameter int ASSOCIATIVITY = 1
)(
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	// 控制信号
	input decode_info_t  ex_decode_info_i, // EX STAGE TODO: REFRACTOR

    input logic ex_valid_i,   // 表示指令在 ex 级是有效的

    input logic m1_valid_i,   // 表示指令在 m1 级是有效的
    input logic m1_taken_i,   // 表示指令在 m1 级接受了后续指令
    output logic m1_busy_o, // 表示 cache 在 m1 级的处理被阻塞，正常情况，只有 M2 级别的状态机请求暂停时会发生阻塞

    input logic m2_valid_i,   // 表示指令在 m1 级是有效的
    input logic m2_taken_i,   // 表示指令在 m2 级的处理已完成，可以接受后续指令
    output logic m2_busy_o, // 表示 cache 在 m2 级的处理被阻塞

	// 流水线数据输入输出
	input  logic[31:0] ex_vaddr_i,   // EX STAGE

	input  logic[31:0] m1_paddr_i,   // M1 STAGE
    output logic[31:0] m1_rdata_o, 
    output logic       m1_rvalid_o,
	input  logic[31:0] m1_wdata_i,   // M1 STAGE

    input logic        m2_uncached_i,
    output logic[31:0] m2_rdata_o, 
    output logic       m2_rvalid_o,

	output logic[31:0] m2_vaddr_o,
	output logic[31:0] m2_paddr_o,

    // 连接一致性总线
    input coherence_bus_req_t creq_i,
    output coherence_bus_resp_t cresp_o,

	// 连接内存总线
	output cache_bus_req_t breq_o,
	input cache_bus_resp_t bresp_i
);

    localparam TAG_ADDR_WIDTH = 28 - CACHE_SHIFT;
    localparam CACHE_WORD_SHIFT_WIDTH = 2;
    localparam CACHE_LINE_ID_WIDTH = 8;
    localparam CACHE_LINE_SHIFT_WIDTH = CACHE_SHIFT - CACHE_LINE_ID_WIDTH - CACHE_WORD_SHIFT_WIDTH;

    // 最简化的 cache 实现
    // 非组相连，4k - 32k 可配置大小
    // cache 项固定为 256 项，4k时行大小为4，16k 时行大小为 16
    // 支持数据早出，支持写数据前递
    // 物理地址线为 28 位，256M 地址空间 （Linux 下，cache 大小限制在 4k 以避免页冲突）
    // 此时 TAG 为 16位 addr + 12位 cache 偏移
    // 支持 cache 指令，由重填状态机完成

    // TAG RAM：1R1W，读端口位于EX级，读取为异步逻辑，加一级寄存器到达 m1 级进行地址比较验证。
    // 写端口位于 m2 级，用于 refill
    logic[ASSOCIATIVITY - 1 : 0][CACHE_LINE_ID_WIDTH - 1 : 0] tag_r_addr;
    logic[ASSOCIATIVITY - 1 : 0][CACHE_LINE_ID_WIDTH - 1 : 0] tag_w_addr;
    logic[ASSOCIATIVITY - 1 : 0] tag_we;
    logic[ASSOCIATIVITY - 1 : 0][TAG_ADDR_WIDTH : 0] tag_r_data;
    logic[ASSOCIATIVITY - 1 : 0][TAG_ADDR_WIDTH : 0] tag_w_data;
    /*FIXME BEGIN*/ // USE IP CORE / XPM MODULE / BLACK BOX
    logic[ASSOCIATIVITY - 1 : 0][255:0][TAG_ADDR_WIDTH : 0] __tag_ram;
    for(genvar i = 0 ; i < ASSOCIATIVITY; i++) begin
        always_ff @(posedge clk) begin
            if(tag_we[i]) __tag_ram[i][tag_w_addr[i]] <= tag_w_data[i];
        end
        assign tag_r_data[i] = __tag_ram[i][tag_r_addr[i]];
    end
    /*FIXME END*/ // USE IP CORE / XPM MODULE / BLACK BOX

    // DIRTY RAM：1R1W，读写端口均位于 m2 级，用于 refill 时候的操作
    logic[ASSOCIATIVITY - 1 : 0][CACHE_LINE_ID_WIDTH - 1 : 0] dirty_r_addr;
    logic[ASSOCIATIVITY - 1 : 0][CACHE_LINE_ID_WIDTH - 1 : 0] dirty_w_addr;
    logic[ASSOCIATIVITY - 1 : 0] dirty_we;
    logic[ASSOCIATIVITY - 1 : 0] dirty_r_data;
    logic[ASSOCIATIVITY - 1 : 0] dirty_w_data;
    /*FIXME BEGIN*/ // USE IP CORE / XPM MODULE / BLACK BOX
    logic[ASSOCIATIVITY - 1 : 0][255:0] __dirty_ram;
    for(genvar i = 0 ; i < ASSOCIATIVITY; i++) begin
        always_ff @(posedge clk) begin
            if(dirty_we[i]) __dirty_ram[i][dirty_w_addr[i]] <= dirty_w_data[i];
        end
        assign dirty_r_data[i] = __dirty_ram[i][dirty_r_addr[i]];
    end
    /*FIXME END*/ // USE IP CORE / XPM MODULE / BLACK BOX

    // REFILL 选择
    logic[ASSOCIATIVITY - 1 : 0] nxt_refill_select_vec_q;
    if(ASSOCIATIVITY != 1) begin
        // 仅在存在多项 CACHE 表项时存在
    end else begin
        assign nxt_refill_select_vec_q = 1'b1;
    end

    // DATA RAM：1R1W，读端口位于 ex / m2,写端口位于 m2
    logic grab_sram_r; // REFILL MACHINE 抢夺读端口
                       // 如若将 DATA RAM 配置为 2R1W，则不需要此信号
    logic[ASSOCIATIVITY - 1 : 0][CACHE_LINE_ID_WIDTH + CACHE_LINE_SHIFT_WIDTH - 1 : 0] sram_r_addr;
    logic[ASSOCIATIVITY - 1 : 0][CACHE_LINE_ID_WIDTH + CACHE_LINE_SHIFT_WIDTH - 1 : 0] sram_w_addr;
    logic[ASSOCIATIVITY - 1 : 0][3:0] sram_we;
    logic[ASSOCIATIVITY - 1 : 0][31:0] sram_r_data;
    logic[ASSOCIATIVITY - 1 : 0][31:0] sram_w_data;
    /*FIXME BEGIN*/ // USE IP CORE / XPM MODULE / BLACK BOX
    logic[ASSOCIATIVITY - 1 : 0][(1 << (CACHE_LINE_SHIFT_WIDTH + CACHE_LINE_ID_WIDTH)) - 1 : 0][3:0][7:0] __sram;
    for(genvar i = 0 ; i < ASSOCIATIVITY ; i++) begin
        logic[CACHE_LINE_ID_WIDTH + CACHE_LINE_SHIFT_WIDTH - 1 : 0] __sram_raddr;
        always_ff @(posedge clk) begin
            __sram_raddr <= sram_r_addr[i];
            for(integer j = 0 ; j < 4 ; j++) begin
                if(sram_we[i][j]) __sram[i][sram_w_addr[i]][j] <= sram_w_data[i][8 * j - 1 -: 8];
            end
        end
        assign sram_r_data[i] = __sram[i][__sram_raddr];
    end
    /*FIXME END*/ // USE IP CORE / XPM MODULE / BLACK BOX

    // SEL RAM: 1R1W，读端口位于EX级，读取为异步逻辑，与输入地址进行提前比较，以在m1级直接确定是否有效。
    // 只在组相连 Cache 中有用，用于提前推测一个 tag 行。
    // 相当于在 组相连 Cache 中加入了一个 直接相连 Cache，以提前取出有效数据。
    // 最高位是额外的 组标记， 标识应该选择哪一路
    logic[TAG_ADDR_WIDTH + $clog2(ASSOCIATIVITY): 0] etag_r_data; // 仅在 M1 级使用， 不需要传递到 M2 级。
    if(ASSOCIATIVITY == 1) begin
        // 直接相连时，早出 tag 即为唯一的一路 tag
        assign etag_r_data = tag_r_data[0];
    end else begin
        /*FIXME BEGIN*/ // USE IP CORE / XPM MODULE / BLACK BOX
        logic[255:0][TAG_ADDR_WIDTH + $clog2(ASSOCIATIVITY): 0] __etag_ram;
        logic[7:0] __etag_w_addr;
        logic[TAG_ADDR_WIDTH + $clog2(ASSOCIATIVITY): 0] __etag_w_data;
        logic __etag_we;
        always_ff@(posedge clk) begin
            if(__etag_we) __etag_ram[__etag_w_addr] <= __etag_w_data;
        end
        assign __etag_w_addr = tag_w_addr[0];
        always_comb begin
            // 不存在优先级，即可以保证同时仅有一位写使能有效
            __etag_w_data = '0;
            __etag_we = '0;
            for(int i = 1 ; i < ASSOCIATIVITY ; i ++) begin
                if(tag_we[i]) begin
                    __etag_we |= 1'b1;
                    __etag_w_data |= {($clog2(ASSOCIATIVITY))'i,tag_w_data[i]};
                end
            end
        end

        assign etag_r_data = __etag_ram[tag_r_addr[0]];
        /*FIXME END*/ // USE IP CORE / XPM MODULE / BLACK BOX
    end

    /*                                        数据部分结束                                        */
    /* ---------------------------------------------------------------------------------------- */
    /*                                        控制部分开始                                        */

    // 控制信号定义
    logic[4:0] ex_ctrl,m1_ctrl_q,ctrl_q; // 管理 cache 行为
    localparam logic[4:0] C_NONE       = 5'b00000;
    localparam logic[4:0] C_READ       = 5'b00001;
    localparam logic[4:0] C_WRITE      = 5'b00010;
    localparam logic[4:0] C_HIT_WB     = 5'b00100;
    localparam logic[4:0] C_INVALID    = 5'b01000;
    localparam logic[4:0] C_INVALID_WB = 5'b10000;

    logic[2:0] ex_fmt,m1_fmt_q,fmt_q;    // 管理对齐行为，解释见下方 RTL
    logic uncached_q;
    logic bus_busy_q;
    // 输出处理逻辑
	// always_comb begin
	// 	case(req_type[1:0])
	// 		`_MEM_TYPE_WORD: begin
	// 			r_data_o = sel_data;
	// 		end
	// 		`_MEM_TYPE_HALF: begin
	// 			if(paddr_o[1])
	// 				r_data_o = {{16{(sel_data[31] & ~req_type[2])}},sel_data[31:16]};
	// 			else
	// 				r_data_o = {{16{(sel_data[15] & ~req_type[2])}},sel_data[15:0]};
	// 		end
	// 		`_MEM_TYPE_BYTE: begin
	// 			if(paddr_o[1])
	// 				if(paddr_o[0])
	// 					r_data_o = {{24{(sel_data[31] & ~req_type[2])}},sel_data[31:24]};
	// 				else
	// 					r_data_o = {{24{(sel_data[23] & ~req_type[2])}},sel_data[23:16]};
	// 			else
	// 				if(paddr_o[0])
	// 					r_data_o = {{24{(sel_data[15] & ~req_type[2])}},sel_data[15:8]};
	// 				else
	// 					r_data_o = {{24{(sel_data[7 ] & ~req_type[2])}},sel_data[7 :0]};
	// 		end
	// 		default: begin
	// 			r_data_o = sel_data;
	// 		end
	// 	endcase
	// end

    // EX 级的接线，只有 DATA RAM 存在冲突，需要一个 mux 接在 DATA RAM 的地址线上。
    logic[CACHE_LINE_ID_WIDTH + CACHE_LINE_SHIFT_WIDTH - 1 : 0] refill_sram_r_addr;
    logic[CACHE_LINE_ID_WIDTH + CACHE_LINE_SHIFT_WIDTH - 1 : 0] pipeline_sram_r_addr;
    for(genvar i = 0 ; i < ASSOCIATIVITY ; i++) begin
        la_mux2#(CACHE_LINE_ID_WIDTH + CACHE_LINE_SHIFT_WIDTH) sram_r_addr_mux(pipeline_sram_r_addr,refill_sram_r_addr,sram_r_addr[i],grab_sram_r);
    end
    assign pipeline_sram_r_addr = ex_vaddr_i[CACHE_SHIFT - 1 : CACHE_WORD_SHIFT_WIDTH];
    for(genvar i = 0 ; i < ASSOCIATIVITY ; i++) begin
        assign tag_r_addr = ex_vaddr_i[CACHE_SHIFT - 1 : CACHE_WORD_SHIFT_WIDTH];
    end

    // EX-M1-M2 级的接线
    logic[ASSOCIATIVITY - 1 : 0][31:0] sram_m1,sram_m1_q,sram_m2,sram_q;
    logic[ASSOCIATIVITY - 1 : 0][TAG_ADDR_WIDTH:0] tag_m1,tag_m1_q,tag_m2,tag_q;
    logic[31:0] m1_vaddr_q,m1_paddr,vaddr_q,paddr_q;
    logic[31:0] m1_esram,esram_q;
    logic m2_evalid_q;
    logic fsm_busy, delay_fsm_busy;
    logic fifo_full_q, pw_empty_q
    logic[ASSOCIATIVITY - 1 : 0] hit_m1, hit_m2, hit_q;
    logic miss_m1, miss_m2, miss_q;

    logic[31:0] m1_wdata,wdata_q;
    logic delay_m1_taken,delay_m2_taken;

    // FSM 的信号，标准版本。
    logic[3:0] fsm_state_q,fsm_state;
    localparam logic[3:0] S_NORMAL    = 4'd0;
    localparam logic[3:0] S_WAIT_BUS  = 4'd1;
    localparam logic[3:0] S_RADR      = 4'd2;
    localparam logic[3:0] S_RDAT      = 4'd3;
    localparam logic[3:0] S_WADR      = 4'd4;
    localparam logic[3:0] S_WDAT      = 4'd5;
    localparam logic[3:0] S_PRADR     = 4'd6;
    localparam logic[3:0] S_PRDAT     = 4'd7;
    localparam logic[3:0] S_WAIT_FULL = 4'd8;

    // 数据控制信号
    logic[3:0] data_strobe;
    logic[1:0] size;

    // EX-M1 流水线寄存器
    always_ff @(posedge clk) begin
        if(m1_taken) begin
            m1_fmt_q <= ex_fmt;
            m1_ctrl_q <= ex_ctrl;
            m1_vaddr_q <= ex_vaddr_i;
        end
    end

    // M1-M2 流水线寄存器
    always_ff @(posedge clk) begin
        if(m2_taken) begin
            fmt_q <= m1_fmt_q;
            ctrl_q <= m1_ctrl_q;
            vaddr_q <= m1_vaddr_q;
            paddr_q <= m1_paddr;
        end
    end

    // delay 的阻塞控制信号
    always_ff @(posedge clk) begin
        delay_m1_taken <= m1_taken_i;
        delay_m2_taken <= m2_taken_i;
    end

    // M1 级的组合逻辑

    // m1_paddr 处理
    assign m1_paddr = m1_paddr_i;

    // sram_m1, tag_m1 处理
    always_comb begin
        sram_m1 = delay_m1_taken ? sram_r_data : sram_m1_q;
        tag_m1 = delay_m1_taken ? tag_r_data : tag_m1_q;
        for(integer i = 0 ; i < ASSOCIATIVITY ; i++) begin
            // 时刻监控对 TAG / DATA 的写入，以及时更新寄存器中的对应值
            for(integer j = 0 ; j < 4 ; j++) begin
                if(sram_we[i][j] && (sram_w_addr[i] == m1_vaddr_q[CACHE_SHIFT - 1 : CACHE_WORD_SHIFT_WIDTH])) begin
                    sram_m1[i][8 * j - 1 -: 8] = sram_w_data[i][8 * j - 1 -: 8];
                end
            end
            if(tag_we[i] && (tag_w_addr[i] == m1_vaddr_q[CACHE_SHIFT - 1 -: CACHE_LINE_ID_WIDTH])) begin
                tag_m1[i] = tag_w_data[i];
            end
        end
    end

    // wdata 对齐处理
    always_comb begin
        // TODO OPTIMIZE: USE MUX3 OR MUX2 TO DISCRIBE LOGIC HERE.
        case(m1_vaddr_q[1:0])
            default: begin
                m1_wdata[31:24] = m1_wdata_i[31:24]; // mux3
                m1_wdata[23:16] = m1_wdata_i[23:16]; // mux2
                m1_wdata[15: 8] = m1_wdata_i[15: 8]; // mux2
                m1_wdata[ 7: 0] = m1_wdata_i[ 7: 0]; // no mux
            end
            3'b01: begin
                m1_wdata[31:24] = m1_wdata_i[31:24];
                m1_wdata[23:16] = m1_wdata_i[23:16];
                m1_wdata[15: 8] = m1_wdata_i[ 7: 0];
                m1_wdata[ 7: 0] = m1_wdata_i[ 7: 0];
            end
            3'b10: begin
                m1_wdata[31:24] = m1_wdata_i[15: 8];
                m1_wdata[23:16] = m1_wdata_i[ 7: 0];
                m1_wdata[15: 8] = m1_wdata_i[ 7: 0];
                m1_wdata[ 7: 0] = m1_wdata_i[ 7: 0];
            end
            3'b11: begin
                m1_wdata[31:24] = m1_wdata_i[ 7: 0];
                m1_wdata[23:16] = m1_wdata_i[ 7: 0];
                m1_wdata[15: 8] = m1_wdata_i[ 7: 0];
                m1_wdata[ 7: 0] = m1_wdata_i[ 7: 0];
            end
        endcase
    end

    // hit_m1, miss_m1 处理
    if(ASSOCIATIVITY == 1) begin
        always_comb begin
            hit_m1 = (m1_paddr[TAG_ADDR_WIDTH + 12 - 1 : 12] == tag_m1[0][TAG_ADDR_WIDTH - 1 : 0]) && tag_m1[TAG_ADDR_WIDTH];
            miss_m1 = ~hit_m1;
        end
    end else begin
        // TODO: ASSOCIATIVITY != 0
    end

    // sram_m1_q, tag_m1_q handler
    always_ff @(posedge clk) begin
        sram_m1_q <= sram_m1;
        tag_m1_q <= tag_m1;
    end

    // M2 级的组合逻辑

    // uncached_q 处理，此信号在外部由寄存器驱动
    assign uncached_q = m2_uncached_i;

    // sram_m2, tag_m2 handler
    always_comb begin
        sram_m2 = m2_taken_i ? sram_m1 : sram_q;
        tag_m2 = m2_taken_i ? tag_m1 : tag_q;
        // TODO: 添加处理过程中，对 sram_m2 向量的更新
        // 注：此时 sram_m2 唯一的来源即为重填，不存在可能的部分字使能写入
        // TAG 在 m2 级并不需要再进行任何的更新了。
    end
    // hit_m2, miss_m2 处理
    always_comb begin
        hit_m2 = m2_taken_i ? hit_m1 : hit_q;
        miss_m2 = m2_taken_i ? miss_m1 : miss_q;
        // TODO: 添加处理过程中，对 HIT MISS 向量的更新
        // 注：只需要对hit向量和 miss 值进行修改即可。 
        // 无论 cached 或者 uncached，结果可以一并放在 way0 ，避免复杂化。
    end
    // wdata_m2 的处理
    always_comb begin
        wdata_m2 = m2_taken_i ? m1_wdata : wdata_q;
        // 不需要进行任何的维护
    end

    // hit_q,miss_q,sram_q,tag_q,wdata_q 的处理
    always_ff @(posedge clk) begin
        sram_q <= sram_m2;
        tag_q <= tag_m2;
        hit_q <= hit_m2;
        miss_q <= miss_m2;
        wdata_q <= wdata_m2;
    end

    always_ff @(posedge clk) begin
        // TODO: Correct this.
        bus_busy_q <= 1'b0;
    end

    // CACHE 核心状态机
    always_comb begin
        fsm_state = fsm_state_q;
        case(fsm_state_q)
            S_NORMAL: begin
                // NORMAL下, 遇到需要处理MISS或者缓存操作需要切换状态
                if((ctrl_q & (C_WRITE | C_READ)) && !uncached_q && miss_q) begin
                    // CACHED READ | WRITE MISS
                    if(bus_busy_q) begin
                        fsm_state = S_WAIT_BUS;
                    end else begin
                        // 若被选择的缓存行为脏,需要写回,否之直接读取新数据。
                        // TODO: 支持组相连
                        if(dirty_r_data[0]) begin
                            fsm_state = S_WADR;
                        end else begin
                            fsm_state = S_RADR;
                        end
                    end
                end
                if((ctrl & C_READ) && uncached_q && miss_q) begin
                    // UNCACHED READ
                    if(bus_busy_q) begin
                        fsm_state = S_WAIT_BUS;
                    end else begin
                        fsm_state = S_PRADR;
                    end
                end
                if((ctrl & C_WRITE) && uncached_q && fifo_full_q) begin
                    // UNCACHED WRITE && FIFO FULL
                    fsm_state = S_WAIT_FULL;
                end
                // TODO: 支持组相连
                if((((ctrl & C_INVALID_WB) && tag_m2[0][TAG_ADDR_WIDTH] && dirty_r_data[0]) ||
                    ((ctrl & C_HIT_WB) && hit_q[0] && dirty_r_data[0])) && miss_q) begin
                        // 一个小技巧：复用 miss_q 标识操作未完成
                    // CACOP WB 请求的CACHE行为脏, 需要写回
                    if(bus_busy) begin
                        fsm_state = S_WAIT_BUS;
                    end else begin
                        fsm_state = S_WADR;
                    end
                end
                // 最高优先级, 当前请求被无效化时, 不可暂停
                if(!m2_valid_i) begin
                    fsm_state = fsm_state_q;
                end
            end
            S_WAIT_BUS: begin
                // WAIT_BUS 需要等待让出总线后继续后面的操作
                if(~bus_busy_q) begin
                    fsm_state = S_NORMAL;
                end
            end
            S_RADR: begin
                // 读地址得到响应后继续后面的操作
                if(bresp_i.ready) begin
                    fsm_state = S_RDAT;
                end
            end
            S_RDAT: begin
                // 读数据拿到最后一个数据后开始后续操作
                if(bresp_i.data_ok && bresp_i.data_last) begin
                    fsm_state = S_NORMAL;
                end
            end
            S_WADR: begin
                // 写地址得到总线响应后继续后面的操作
                if(bresp_i.ready) begin
                    fsm_state = S_WDAT;
                end
            end
            S_WDAT: begin
                // 最后一个写数据得到总线响应后开始后续操作
                if(bresp_i.data_ok && breq_o.data_last) begin
                    // 区别INVALIDATE情况和MISS REFETCH情况
                    if(ctrl & C_READ || ctrl & C_WRITE) fsm_state = S_RADR;
                    else fsm_state = S_NORMAL;
                end
            end
            S_PRADR: begin
                // 读地址得到响应后继续后面的操作
                if(bresp_i.ready) begin
                    fsm_state = S_PRDAT;
                end
            end
            S_PRDAT: begin
                // 读数据得到响应后继续后面的操作
                if(bresp_i.data_ok && bresp_i.data_last) begin
                    fsm_state = S_NORMAL;
                end
            end
            S_WAIT_FULL: begin
                // FIFO不为空时候跳出此状态
                if(!fifo_full_q) begin
                    fsm_state = S_NORMAL;
                end
            end
        endcase
    end

    // sram 写控制
    // 控制信号 sram_w_addr,
    // sram_w_data, sram_we
    always_comb begin
        // TODO: 支持组相连
        sram_w_data[0] = (fsm_state == S_NORMAL) ? wdata_q : bresp_i.r_data;
        sram_w_addr[0] = (fsm_state == S_NORMAL) ? paddr_q[CACHE_SHIFT - 1 : CACHE_WORD_SHIFT_WIDTH];
        sram_we[0] = (hit_q[0] && (ctrl_q & C_WRITE) && !uncached_q) ? data_strobe : 4'b0000;
    end

    // 写回 FIFO 状态机
    // 控制信息, FIFO写回状态机
    localparam logic[1:0] S_FEMPTY = 2'd0;
    localparam logic[1:0] S_FADR   = 2'd1;
    localparam logic[1:0] S_FDAT   = 2'd2;
    logic[1:0] fifo_fsm_state_q,fifo_fsm_state;

    typedef struct packed {
        logic [31:0] addr;
        logic [31:0] data;
        logic [ 3:0] strobe;
        logic [ 1:0] size;
    } pw_fifo_t;
    pw_fifo_t pw_req,pw_handling;
    /*FIXME BEGIN*/ // USE IP CORE / XPM MODULE / BLACK BOX
    pw_fifo_t [WB_FIFO_DEPTH - 1 : 0] pw_fifo;
    logic pw_w_e,pw_r_e,pw_empty_q;
    logic[$clog2(WB_FIFO_DEPTH) : 0] pw_w_ptr,pw_r_ptr,pw_cnt;
    assign pw_cnt = pw_w_ptr - pw_r_ptr;
    // assign pw_empty_q = pw_cnt == '0;
    // assign fifo_full = pw_cnt[$clog2(WB_FIFO_DEPTH)];
    always_ff @(posedge clk) begin
        fifo_full_q <= pw_cnt[$clog2(WB_FIFO_DEPTH)] || ((&pw_cnt[$clog2(WB_FIFO_DEPTH) - 1 : 0]) && pw_w_e && !pw_r_e);
        pw_empty_q <= (pw_cnt == '0) || ((pw_cnt == 1) && pw_r_e && !pw_w_e);
    end
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            pw_w_ptr <= '0;
        end else if(pw_w_e && !(pw_empty_q && pw_r_e)) begin
            pw_w_ptr <= pw_w_ptr + 1'd1;
        end
    end
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            pw_r_ptr <= '0;
        end else if(pw_r_e && !pw_empty_q) begin
            pw_r_ptr <= pw_r_ptr + 1'd1;
        end
    end
    always_ff @(posedge clk) begin
        if(pw_r_e) begin
            if(!pw_empty_q) pw_handling <= pw_fifo[pw_r_ptr[$clog2(WB_FIFO_DEPTH) - 1: 0]];
            else          pw_handling <= pw_req;
        end
    end
    always_ff @(posedge clk) begin
        if(pw_w_e) begin
            pw_fifo[pw_w_ptr[$clog2(WB_FIFO_DEPTH) - 1: 0]] <= pw_req;
        end
    end
    /*FIXME END*/ // USE IP CORE / XPM MODULE / BLACK BOX
    always_comb begin
        pw_req.addr   = paddr_q;
        pw_req.data   = wdata_q;
        pw_req.strobe = data_strobe;
        pw_req.size   = size;
    end
    always_comb begin
        fifo_fsm_state = fifo_fsm_state_q;
        case(fifo_fsm_state_q)
            S_FEMPTY: begin
                if(pw_w_e) begin
                    fifo_fsm_state = S_FADR;
                end
            end
            S_FADR: begin
                if(bresp_i.ready) begin
                    fifo_fsm_state = S_FDAT;
                end
            end
            S_FDAT: begin
                if(bresp_i.data_ok) begin
                    if(pw_empty_q && !pw_w_e) begin
                        // 没有后续请求
                        fifo_fsm_state = S_FEMPTY;
                    end else begin
                        // 有后续请求
                        fifo_fsm_state = S_FADR;
                    end
                end
            end
        endcase
    end

    // W-R使能
    // pw_r_e pw_w_e
    assign pw_r_e = (fifo_fsm_state_q == S_FDAT && fifo_fsm_state == S_FADR) || (fifo_fsm_state_q == S_FEMPTY && fifo_fsm_state == S_FADR);
    assign pw_w_e = !stall && uncached_q && (ctrl == C_WRITE) && !request_clr_m2_i && !fifo_full_q;


endmodule