`include "common.svh"
`include "decoder.svh"
`include "lsu_types.svh"

/*--JSON--{"module_name":"lsu","module_ver":"100","module_type":"module"}--JSON--*/

module lsu #(
    parameter int CACHE_SHIFT = 12, // options from 12 - 14
    parameter bit EARLY_OUT = 1'b1,
    parameter bit MULTI_READ_PORT = 1'b1,
    parameter bit MULTI_WRITE_PORT = 1'b1,
)(
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	// 流水线数据输入输出
	input  logic[1:0][31:0] ex_vaddr_i,   // EX STAGE

	// 控制信号
    input logic[1:0] m1_valid_i,   // 表示指令在 m1 级是有效的
    input logic m1_taken_i,   // 表示指令在 m1 级接受了后续指令
    input logic[1:0][4:0] m1_ctrl_i,
    input logic[1:0][2:0] m1_fmt_i,
    output logic m1_busy_o, // 表示 cache 在 m1 级的处理被阻塞

    input logic[1:0] m2_valid_i,   // 表示指令在 m1 级是有效的
    input logic m2_taken_i,   // 表示指令在 m2 级的处理已完成，可以接受后续指令
    input logic[1:0][4:0] m2_ctrl_i,
    input logic[1:0][2:0] m2_fmt_i,
    output logic m2_busy_o, // 表示 cache 在 m2 级的处理被阻塞


	input  logic[1:0][31:0] m1_paddr_i,   // M1 STAGE
    input  logic[1:0]       m1_uncached_i,
    output logic[1:0][31:0] m1_rdata_o, 
    output logic[1:0]       m1_rvalid_o,
	input  logic[1:0][31:0] m1_wdata_i,   // M1 STAGE

    input  logic[1:0]       m2_uncached_i,
    output logic[1:0][31:0] m2_rdata_o, 
    output logic[1:0]       m2_rvalid_o,

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
    typedef struct packed {
        logic[TAG_ADDR_WIDTH - 1 : 0] addr;
        logic valid;
    } tag_t;
    function logic[TAG_ADDR_WIDTH - 1 : 0] tagaddr(logic[31:0] va);
		return va[27 : CACHE_SHIFT];
	endfunction
	function logic[CACHE_LINE_ID_WIDTH - 1 : 0] tramaddr(logic[31:0] va);
		return va[CACHE_SHIFT - 1 -: CACHE_LINE_ID_WIDTH];
	endfunction
	function logic[CACHE_SHIFT - CACHE_WORD_SHIFT_WIDTH - 1 : 0] dramaddr(logic[31:0] va);
		return va[CACHE_SHIFT - 1 : CACHE_WORD_SHIFT_WIDTH];
	endfunction
    function logic[31:0] mkrdata(logic[31:0] raw, logic[1:0] pa, logic[3:0] fmt);
    	case(fmt[1:0])
			`_MEM_TYPE_WORD: begin
				mkrdata = raw;
			end
			`_MEM_TYPE_HALF: begin
				if(pa[1])
					mkrdata = {{16{(raw[31] & ~fmt[2])}},raw[31:16]};
				else
					mkrdata = {{16{(raw[15] & ~fmt[2])}},raw[15:0]};
			end
			`_MEM_TYPE_BYTE: begin
				if(pa[1])
					if(pa[0])
						mkrdata = {{24{(raw[31] & ~fmt[2])}},raw[31:24]};
					else
						mkrdata = {{24{(raw[23] & ~fmt[2])}},raw[23:16]};
				else
					if(pa[0])
						mkrdata = {{24{(raw[15] & ~fmt[2])}},raw[15:8]};
					else
						mkrdata = {{24{(raw[7 ] & ~fmt[2])}},raw[7 :0]};
			end
			default: begin
				mkrdata = raw;
			end
		endcase
    endfunction
    function logic cache_hit(tag_t tag,logic[31:0] pa);
        return tag.valid && (tagaddr(pa) == tag.addr);
    endfunction
    // TAG RAM：1R1W，读端口位于EX级，读取为异步逻辑，加一级寄存器到达 m1 级进行地址比较验证。
    // 写端口位于 m2 级，用于 refill
    
    // 备注：此实现为一个伪实现，不可综合，仅仅用于仿真性能测试研究体系结构
    logic[(1 << (CACHE_SHIFT - CACHE_WORD_SHIFT_WIDTH)) - 1 : 0][31:0] data_ram;
    tag_t[255:0] tag_ram;
    localparam logic[4:0] C_NONE       = 5'b00000;
    localparam logic[4:0] C_READ       = 5'b00001;
    localparam logic[4:0] C_WRITE      = 5'b00010;
    localparam logic[4:0] C_HIT_WB     = 5'b00100;
    localparam logic[4:0] C_INVALID    = 5'b01000;
    localparam logic[4:0] C_INVALID_WB = 5'b10000;

    logic[1:0] uncached;
    logic[1:0] need_op;

    logic[1:0] op_ready_q, op_ready;
    logic[1:0][31:0] uncached_rdata;

    // M2 级的数据输出
    logic[1:0][31:0] m2_paddr,m2_wdata;
    logic[1:0][3:0] data_strobe;

    for(integer i = 0 ; i < MULTI_READ_PORT ?  2 : 1 ; i++) begin
        // M1 级的数据输出
        always_comb begin
            m1_busy_o = 1'b0; // 永远不阻塞
            m1_rdata_o[i] = data_ram[dramaddr(m1_paddr_i[i])];
            m1_rvalid_o[i] = cache_hit(tag_ram[tramaddr(m1_paddr_i[i])], m1_paddr_i[i]) &&
            m1_valid_i[i] && (m1_ctrl_i[i] == C_READ) && !m1_uncached_i[i] &&
            !((m2_valid_i[0] && m2_ctrl_i[0] == C_WRITE) || (m2_valid_i[1] && m2_ctrl_i[1] == C_WRITE)) &&
            (m1_fmt_i[i] == `_MEM_TYPE_WORD);
        end
        // wdata 对齐处理
        logic[31:0] m1_wdata;
        always_comb begin
            // TODO OPTIMIZE: USE MUX3 OR MUX2 TO DISCRIBE LOGIC HERE.
            case(m1_vaddr_q[1:0])
                default: begin
                    m1_wdata[31:24] = m1_wdata_i[i][31:24]; // mux3
                    m1_wdata[23:16] = m1_wdata_i[i][23:16]; // mux2
                    m1_wdata[15: 8] = m1_wdata_i[i][15: 8]; // mux2
                    m1_wdata[ 7: 0] = m1_wdata_i[i][ 7: 0]; // no mux
                end
                3'b01: begin
                    m1_wdata[31:24] = m1_wdata_i[i][31:24];
                    m1_wdata[23:16] = m1_wdata_i[i][23:16];
                    m1_wdata[15: 8] = m1_wdata_i[i][ 7: 0];
                    m1_wdata[ 7: 0] = m1_wdata_i[i][ 7: 0];
                end
                3'b10: begin
                    m1_wdata[31:24] = m1_wdata_i[i][15: 8];
                    m1_wdata[23:16] = m1_wdata_i[i][ 7: 0];
                    m1_wdata[15: 8] = m1_wdata_i[i][ 7: 0];
                    m1_wdata[ 7: 0] = m1_wdata_i[i][ 7: 0];
                end
                3'b11: begin
                    m1_wdata[31:24] = m1_wdata_i[i][ 7: 0];
                    m1_wdata[23:16] = m1_wdata_i[i][ 7: 0];
                    m1_wdata[15: 8] = m1_wdata_i[i][ 7: 0];
                    m1_wdata[ 7: 0] = m1_wdata_i[i][ 7: 0];
                end
            endcase
        end
        always_comb begin
            data_strobe[i] = 4'b0000;
            case(m2_fmt_i[1:0])
                `_MEM_TYPE_WORD:   data_strobe[i] = 4'b1111; // WORD
                `_MEM_TYPE_HALF:   data_strobe[i] = 4'b0011 << {m2_paddr[i][1],1'b0};
                `_MEM_TYPE_BYTE:   data_strobe[i] = 4'b0001 <<  m2_paddr[i][1:0];
                default:           data_strobe[i] = 4'b0000; // IMPOSIBLE
            endcase
        end
        always_ff @(posedge clk) begin
            if(m2_taken_i) begin
                m2_paddr[i] <= m1_paddr_i[i];
                m2_wdata[i] <= m1_wdata;
            end
        end
        always_comb begin
            m2_rdata_o[i] = mkrdata(m2_uncached_i ? uncached_rdata[i] : data_ram[dramaddr(m2_paddr[i])],m2_paddr[i],m2_fmt_i[i]);
            m2_rvalid_o[i] = ((cache_hit(tag_ram[tramaddr(m2_paddr[i])], m2_paddr[i]) && !m2_uncached_i[i]) || 
                              (!op_ready_q[i] && m2_uncached_i[i] )) && (m2_ctrl_i[i] == C_READ) && m2_valid_i[i];
            need_op[i] = m2_valid_i[i] && !op_ready_q[i] && ((m2_uncached_i[i]) || 
                              (!m2_uncached_i[i]) || 
                              ((m2_ctrl_i[i] & (C_INVALID | C_INVALID_WB | C_HIT_WB)) != 0));
        end
    end

    logic[3:0] fsm_state_q,fsm_state;
    parameter logic[3:0] S_NORMAL = 0;
    parameter logic[3:0] S_RADR   = 1;
    parameter logic[3:0] S_RDAT   = 2;
    parameter logic[3:0] S_WADR   = 3;
    parameter logic[3:0] S_WDAT   = 4;
    parameter logic[3:0] S_PRADR  = 5;
    parameter logic[3:0] S_PRDAT  = 6;
    parameter logic[3:0] S_PWADR  = 7;
    parameter logic[3:0] S_PWDAT  = 8;
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            fsm_state_q <= S_NORMAL;
        end else begin
            fsm_state_q <= fsm_state;
        end
    end
    logic[CACHE_SHIFT - CACHE_WORD_SHIFT_WIDTH - CACHE_LINE_ID_WIDTH - 1 : 0] refill_cnt_q, refill_cnt;
    logic miss_sel_q, miss_sel;
    always_comb begin
        miss_sel = miss_sel_q;
        op_ready = op_ready_q;
        case(fsm_state_q)
            S_NORMAL: begin
                if((~op_ready_q & need_op) != '0) begin
                    miss_sel = ~miss_sel_q;
                    if((m2_ctrl_i[miss_sel] & (C_HIT_WB | C_INVALID_WB)) != '0) begin
                    end
                end else begin
                    miss_sel = '0;
                end
            end
        endcase
    end

endmodule