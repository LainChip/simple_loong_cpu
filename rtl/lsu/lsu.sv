`include "common.svh"
`include "lsu_types.svh"

`ifdef __DLSU_VER_1

module lsu (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	// 控制信号
	input decode_info_t[1:0] decode_info_i,
	
	// 流水线数据输入输出
	input logic[1:0][31:0] vaddr_i,
	input logic[1:0][31:0] paddr_i, // M2 STAGE
	input logic[1:0][31:0] w_data_i,  // M2 STAGE
	output logic[1:0][31:0] r_data_o,

	// 连接内存总线
	output cache_bus_req_t bus_req_o,
	input cache_bus_req_t bus_resp_i,

	// 握手信号
	output busy,
	input stall
);

	typedef struct packed{
		logic mem_sel_1;
		mem_type_t mem_type;
    	mem_write_t mem_write;
    	mem_valid_t mem_valid;
    	logic[31:0] mem_addr;
	} inner_mem_req_t;

	inner_mem_req_t mem_req_comb,mem_req_stage_1,mem_req_stage_2;
	logic[2:0] fsm_state,fsm_state_next;
	logic transfer_done;
	localparam STATE_IDLE = 3'b001;
	localparam STATE_ADDR = 3'b010;
	localparam STATE_DATA = 3'b100;

	// 获取需要的控制信息，进行流水
	always_comb begin
		mem_req_comb.mem_addr = '0;
		{mem_req_comb.mem_type,mem_req_comb.mem_write,mem_req_comb.mem_valid} =
		{decode_info_i[0].m1.mem_type,decode_info_i[0].m1.mem_write,decode_info_i[0].m1.mem_valid} | 
		{decode_info_i[1].m1.mem_type,decode_info_i[1].m1.mem_write,decode_info_i[1].m1.mem_valid};
		if(decode_info_i[1].m1.mem_valid) begin
			mem_req_comb.mem_addr = vaddr_i[1];
		end else begin
			mem_req_comb.mem_addr = vaddr_i[0];
		end
		mem_req_comb.mem_sel_1 = decode_info_i[1].m1.mem_valid;
	end
	always_ff begin
		if(clk) begin
			mem_req_stage_1 <= '0;
			mem_req_stage_2 <= '0;
		end else if(~busy & ~stall) begin
			mem_req_stage_1 <= mem_req_comb;
			{mem_req_stage_2.mem_type,mem_req_stage_2.mem_write,mem_req_stage_2.mem_sel_1} <= 
			{mem_req_stage_1.mem_type,mem_req_stage_1.mem_write,mem_req_stage_1.mem_sel_1};
			if(transfer_done) begin
				mem_req_stage_2.mem_valid <= '0;
			end else begin
				mem_req_stage_2.mem_valid <= mem_req_stage_1.mem_valid;
			end
			mem_req_stage_2.mem_addr <= paddr_i[mem_req_stage_1.mem_sel_1];
		end
	end

	// 核心状态机，从总线获取读取数据，或写入数据 并返回
	assign transfer_done = ((mem_req_stage_2.mem_write & bus_req_o.data_last) | 
				(~mem_req_stage_2.mem_write & bus_resp_i.data_last)) & bus_resp_i.data_ok & bus_req_o.data_ok;
	always_comb begin
		fsm_state_next = fsm_state;
		case(fsm_state)
			STATE_IDLE:begin
				if(mem_req_stage_2.mem_valid) begin
					fsm_state_next = STATE_ADDR;
				end
			end
			STATE_ADDR:begin
				if(bus_resp_i.ready) begin
					fsm_state_next = STATE_DATA;
				end
			end
			STATE_DATA:begin
				if(transfer_done) begin
					fsm_state_next = STATE_IDLE;
				end
			end
		endcase
	end

	// 总线请求赋值
	always_comb begin
		bus_req_o.valid = fsm_state == STATE_ADDR;
		bus_req_o.write = mem_req_stage_2.mem_write;
		bus_req_o.burst = '0;
		bus_req_o.cached = '0;
		bus_req_o.addr = mem_req_stage_2.mem_addr;

		bus_req_o.w_data = w_data_i[mem_req_stage_2.mem_sel_1] << mem_req_stage_2.mem_addr[1:0];
		case(mem_req_stage_2.mem_type)
			`MEM_TYPE_WORD: begin
				bus_req_o.data_strobe = 4'b1111;
			end
			`MEM_TYPE_HALF: begin
				bus_req_o.data_strobe = (4'b0011 << mem_req_stage_2.mem_addr[1]);
			end
			`MEM_TYPE_BYTE: begin
				bus_req_o.data_strobe = (4'b0001 << mem_req_stage_2.mem_addr[1:0]);
			end
		endcase
		bus_req_o.data_ok = fsm_state == STATE_DATA;
		bus_req_o.data_last = fsm_state == STATE_DATA;
	end

	// 返回请求处理
	

endmodule : lsu

`endif