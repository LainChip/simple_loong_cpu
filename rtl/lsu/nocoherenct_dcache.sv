/*--JSON--{"module_name":"lsu","module_ver":"10","module_type":"module"}--JSON--*/

module lsu #(
    parameter int CACHE_SHIFT = 12, // options from 12 - 14
    parameter int ASSOCIATIVITY = 1
)(
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	// 控制信号
	input decode_info_t  ex_decode_info_i, // EX STAGE TODO: REFRACTOR

    input logic ex_valid,   // 表示指令在 ex 级是有效的

    input logic m1_valid,   // 表示指令在 m1 级是有效的
    input logic m1_taken,   // 表示指令在 m1 级接受了后续指令
    output logic m1_busy_o, // 表示 cache 在 m1 级的处理被阻塞

    input logic m2_valid,   // 表示指令在 m1 级是有效的
    input logic m2_taken,   // 表示指令在 m2 级的处理已完成，可以接受后续指令
    output logic m2_busy_o, // 表示 cache 在 m2 级的处理被阻塞

	// 流水线数据输入输出
	input  logic[31:0] ex_vaddr_i,   // EX STAGE
	input  logic[31:0] m1_paddr_i,   // M1 STAGE
    output logic[31:0] m1_rdata_o, 
    output logic       m1_rvalid_o,

	input logic[31:0]  m2_wdata_i,  // M2 STAGE
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
	input cache_bus_resp_t bresp_i,

	// 握手信号
	output logic busy_o,
	input stall_i
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
    logic[ASSOCIATIVITY - 1 : 0][255:0][CACHE_LINE_ID_WIDTH - 1 : 0] __tag_ram;
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
    logic[ASSOCIATIVITY - 1 : 0] sram_we;
    logic[ASSOCIATIVITY - 1 : 0][31:0] sram_r_data;
    logic[ASSOCIATIVITY - 1 : 0][31:0] sram_w_data;
    /*FIXME BEGIN*/ // USE IP CORE / XPM MODULE / BLACK BOX
    logic[ASSOCIATIVITY - 1 : 0][(1 << (CACHE_LINE_SHIFT_WIDTH + CACHE_LINE_ID_WIDTH)) - 1 : 0][31:0] __sram;
    for(genvar i = 0 ; i < ASSOCIATIVITY ; i++) begin
        logic[CACHE_LINE_ID_WIDTH + CACHE_LINE_SHIFT_WIDTH - 1 : 0] __sram_raddr;
        always_ff @(posedge clk) begin
            __sram_raddr <= sram_r_addr[i];
            if(sram_we[i]) __sram[i][sram_w_addr[i]] <= sram_w_data[i];
        end
        assign sram_r_data[i] = __sram[i][__sram_raddr];
    end
    /*FIXME END*/ // USE IP CORE / XPM MODULE / BLACK BOX

    // SEL RAM: 1R1W，读端口位于EX级，读取为异步逻辑，与输入地址进行提前比较，以在m1级直接确定是否有效。
    // 只在组相连 Cache 中有用，用于提前推测一个 tag 行。
    // 相当于在 组相连 Cache 中加入了一个 直接相连 Cache，以提前取出有效数据。
    // 最高位是额外的 组标记， 标识应该选择哪一路
    logic[TAG_ADDR_WIDTH + $clog2(ASSOCIATIVITY): 0] etag_r_data;
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
    logic[2:0] ex_ctrl,m1_ctrl_q,ctrl_q; // 管理 cache 行为
    localparam logic[2:0] C_NONE       = 3'd0;
    localparam logic[2:0] C_READ       = 3'd1;
    localparam logic[2:0] C_WRITE      = 3'd2;
    localparam logic[2:0] C_HIT_WB     = 3'd3;
    localparam logic[2:0] C_INVALID    = 3'd4;
    localparam logic[2:0] C_INVALID_WB = 3'd5;

    logic[2:0] ex_fmt,m1_fmt_q,fmt_q;    // 管理对齐行为，解释间下方 RTL
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

    // EX-M1 流水线寄存器
    always_ff @(posedge clk) begin

    end

    // M1 级的接线

    // M2 级的接线，这一级的信号不需要前缀，因为是状态机所在的流水级。

endmodule