`include "common.svh"
`include "decoder.svh"
`include "lsu_types.svh"

`ifdef __DLSU_VER_1

module lsu (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	// 控制信号
	input decode_info_t  decode_info_i,
	input logic request_valid_i,
	
	// 流水线数据输入输出
	input logic[31:0] vaddr_i,
	input logic[31:0] paddr_i, // M2 STAGE
	input logic[31:0] w_data_i,  // M2 STAGE
	output logic[31:0] w_data_o,
	input logic request_clr_m2_i,
	input logic request_clr_m1_i,
	output logic[31:0] r_data_o,

	output logic[31:0] vaddr_o,
	output logic[31:0] paddr_o,

	// 连接内存总线
	output cache_bus_req_t bus_req_o,
	input cache_bus_resp_t bus_resp_i,

	// 握手信号
	output busy_o,
	input stall_i
);

	typedef struct packed{
		mem_type_t mem_type;
    	mem_write_t mem_write;
    	mem_valid_t mem_valid;
    	logic[31:0] mem_addr;
		logic[31:0] mem_vaddr;
	} inner_mem_req_t;

	inner_mem_req_t mem_req_comb,mem_req_stage_1,mem_req_stage_2;
	logic[31:0] r_data_handled,r_data;
	logic[2:0] fsm_state,fsm_state_next;
	logic transfer_done;
	localparam STATE_IDLE = 3'b001;
	localparam STATE_ADDR = 3'b010;
	localparam STATE_DATA = 3'b100;

	// 输出数据
	assign r_data_o = r_data;

	// 获取需要的控制信息，进行流水
	always_comb begin
		{mem_req_comb.mem_type,mem_req_comb.mem_write,mem_req_comb.mem_valid} =
		{decode_info_i.m1.mem_type,decode_info_i.m1.mem_write,decode_info_i.m1.mem_valid & request_valid_i};
		mem_req_comb.mem_addr = vaddr_i;
		mem_req_comb.mem_vaddr = vaddr_i;
	end
	always_ff@(posedge clk) begin
		if(~rst_n) begin
			mem_req_stage_1.mem_valid <= '0;
			mem_req_stage_2.mem_valid <= '0;
		end else if(request_clr_m1_i) begin
			mem_req_stage_1.mem_valid <= '0;
			mem_req_stage_2.mem_valid <= '0;
		end else if(request_clr_m2_i) begin
			mem_req_stage_1.mem_valid <= '0;
			mem_req_stage_2.mem_valid <= '0;
		end else if(transfer_done) begin 
			mem_req_stage_2.mem_valid <= '0;
		end else if(~busy_o & ~stall_i) begin
			mem_req_stage_1 <= mem_req_comb;
			{mem_req_stage_2.mem_type,mem_req_stage_2.mem_write,mem_req_stage_2.mem_vaddr} <= 
			{mem_req_stage_1.mem_type,mem_req_stage_1.mem_write,mem_req_stage_1.mem_vaddr};
			mem_req_stage_2.mem_addr <= paddr_i;
			mem_req_stage_2.mem_valid <= mem_req_stage_1.mem_valid;
		end
	end

	// 核心状态机，从总线获取读取数据，或写入数据 并返回
	assign transfer_done = ((mem_req_stage_2.mem_write & bus_req_o.data_last) | 
				(~mem_req_stage_2.mem_write & bus_resp_i.data_last)) & bus_resp_i.data_ok & bus_req_o.data_ok;
	always_comb begin
		fsm_state_next = fsm_state;
		case(fsm_state)
			STATE_IDLE:begin
				if(mem_req_stage_2.mem_valid & ~request_clr_m2_i) begin
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
			default:begin
				fsm_state_next = fsm_state;
			end
		endcase
	end
	assign busy_o = (fsm_state != STATE_IDLE) | mem_req_stage_2.mem_valid;
	always_ff @(posedge clk) begin
		if(~rst_n) begin
			fsm_state <= STATE_IDLE;
		end else begin
			fsm_state <= fsm_state_next;
		end
	end

	// 总线请求赋值
	always_comb begin
		bus_req_o.valid = fsm_state == STATE_ADDR;
		bus_req_o.write = mem_req_stage_2.mem_write;
		bus_req_o.burst = '0;
		bus_req_o.cached = '0;
		bus_req_o.addr = mem_req_stage_2.mem_addr;

		bus_req_o.w_data = w_data_i << {mem_req_stage_2.mem_addr[1:0],3'b000};
		case(mem_req_stage_2.mem_type[1:0])
			`_MEM_TYPE_WORD: begin
				bus_req_o.data_strobe = 4'b1111;
			end
			`_MEM_TYPE_HALF: begin
				bus_req_o.data_strobe = (4'b0011 << {mem_req_stage_2.mem_addr[1],1'b0});
			end
			`_MEM_TYPE_BYTE: begin
				bus_req_o.data_strobe = (4'b0001 << mem_req_stage_2.mem_addr[1:0]);
			end
			default: begin
				bus_req_o.data_strobe = 4'b0000;
			end
		endcase
		bus_req_o.data_ok = fsm_state == STATE_DATA;
		bus_req_o.data_last = fsm_state == STATE_DATA;
	end

	// 输出数据处理
	always_comb begin
		case(mem_req_stage_2.mem_type[1:0])
			`_MEM_TYPE_WORD: begin
				r_data_handled = bus_resp_i.r_data;
			end
			`_MEM_TYPE_HALF: begin
				if(mem_req_stage_2.mem_addr[1])
					r_data_handled = {{16{(bus_resp_i.r_data[31] & ~mem_req_stage_2.mem_type[2])}},bus_resp_i.r_data[31:16]};
				else
					r_data_handled = {{16{(bus_resp_i.r_data[15] & ~mem_req_stage_2.mem_type[2])}},bus_resp_i.r_data[15:0]};
			end
			`_MEM_TYPE_BYTE: begin
				if(mem_req_stage_2.mem_addr[1])
					if(mem_req_stage_2.mem_addr[0])
						r_data_handled = {{24{(bus_resp_i.r_data[31] & ~mem_req_stage_2.mem_type[2])}},bus_resp_i.r_data[31:24]};
					else
						r_data_handled = {{24{(bus_resp_i.r_data[23] & ~mem_req_stage_2.mem_type[2])}},bus_resp_i.r_data[23:16]};
				else
					if(mem_req_stage_2.mem_addr[0])
						r_data_handled = {{24{(bus_resp_i.r_data[15] & ~mem_req_stage_2.mem_type[2])}},bus_resp_i.r_data[15:8]};
					else
						r_data_handled = {{24{(bus_resp_i.r_data[7 ] & ~mem_req_stage_2.mem_type[2])}},bus_resp_i.r_data[7 :0]};
			end
			default: begin
				r_data_handled = bus_resp_i.r_data;
			end
		endcase
	end

	assign vaddr_o = mem_req_stage_2.mem_vaddr;
	assign paddr_o = mem_req_stage_2.mem_addr;
	assign w_data_o = bus_req_o.w_data & {{8{bus_req_o.data_strobe[3]}},{8{bus_req_o.data_strobe[2]}},{8{bus_req_o.data_strobe[1]}},{8{bus_req_o.data_strobe[0]}}};

	always_ff @(posedge clk) begin
		if(transfer_done) begin
			r_data <= r_data_handled;
		end
	end

endmodule

`endif
