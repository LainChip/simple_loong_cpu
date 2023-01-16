`include "common.svh"
`include "decoder.svh"

// I cache的实现中实际包含解码与icache逻辑两部分
// 对于外界的接口，外界输入一个pc信号，获得解码后的多组指令
// 对于每次解码得到的指令数可以配置，对外部全部链接到一个cache_bus握手接口上

module icache #(
	parameter int FETCH_SIZE = 2,
	parameter int ATTACHED_INFO_WIDTH = 32
)(
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	
	input  logic [31:0]vpc_i,
	input  logic [31:0]ppc_i,
	input  logic [FETCH_SIZE - 1 : 0] valid_i,
	input  logic [ATTACHED_INFO_WIDTH - 1 : 0] attached_i,

	output logic [31:0]vpc_o,
	output logic [31:0]ppc_o,
	output logic [FETCH_SIZE - 1 : 0] valid_o,
	output logic [ATTACHED_INFO_WIDTH - 1 : 0] attached_o,
	output decode_info_t [FETCH_SIZE - 1 : 0] decode_output_o,

	input  logic stall_i,
	output logic busy_o,
	input  logic clr_i,

	output cache_bus_req_t bus_req_o,
	input cache_bus_resp_t bus_resp_i
);

	logic [31:0] pc_stage_1, pc_stage_2, fetch_addr, inst;
	logic [FETCH_SIZE - 1 : 0] valid_stage_1, valid_stage_2;
	logic [ATTACHED_INFO_WIDTH - 1 : 0] attached_stage_1, attached_stage_2;
	logic [31:0][7:0] inst_string;
	decode_info_t decode_info_tmp;

	logic stall_pipe, transfer_done;

	logic [FETCH_SIZE - 1 : 0] fetch_need;
	logic [$clog2(FETCH_SIZE) - 1 : 0] fetch_offs;

	logic[2:0] fsm_state,fsm_state_next;
	localparam STATE_IDLE = 3'b001;
	localparam STATE_ADDR = 3'b010;
	localparam STATE_DATA = 3'b100;

	// 暂停逻辑
	assign stall_pipe = stall_i | busy_o;

	// 流水线逻辑，需要正确处理 stall 和 clr
	always_ff @(posedge clk) begin
		if(~rst_n) begin
			pc_stage_1 <= '0;
			valid_stage_1 <= '0;
			attached_stage_1 <= '0;
		end else begin
			if(clr_i) begin
				pc_stage_1 <= '0;
				valid_stage_1 <= '0;
				attached_stage_1 <= '0;
			end else if(~stall_pipe) begin
				pc_stage_1 <= vpc_i;
				valid_stage_1 <= valid_i;
				attached_stage_1 <= attached_i;
			end
		end
	end
	always_ff @(posedge clk) begin
		if(~rst_n) begin
			pc_stage_2 <= '0;
			valid_stage_2 <= '0;
			attached_stage_2 <= '0;
		end else begin
			if(clr_i) begin
				pc_stage_2 <= '0;
				valid_stage_2 <= '0;
				attached_stage_2 <= '0;
			end else if(~stall_pipe) begin
				pc_stage_2 <= pc_stage_1;
				valid_stage_2 <= valid_stage_1;
				attached_stage_2 <= attached_stage_1;
			end
		end
	end

	// Fetched over 逻辑，记录获取到的区块
	always_ff @(posedge clk) begin : proc_fetch_need
		if(~rst_n) begin
			fetch_need <= '0;
		end else begin
			// if(clr_i) begin
			// 	fetch_need <= '0;
			// end else 
			if(~stall_pipe) begin
				fetch_need <= valid_stage_1;
			end else if(transfer_done)begin
				fetch_need[fetch_offs] <= 1'b0;
			end
		end
	end

	// 内部暂停逻辑，当没有完成fetch的时候，拉高busy_o
	assign busy_o = |fetch_need;

	// find one 逻辑，获取下一个需要fetch的地址
	always_comb begin
		fetch_offs = 0;
		for(integer i = FETCH_SIZE - 1; i >= 0; i-=1) begin
			if(fetch_need[i]) begin
				fetch_offs = i[$clog2(FETCH_SIZE) - 1 : 0];
			end
		end 
	end

	// 生成fetch地址
	assign fetch_addr = {pc_stage_2[31 : 2 + $clog2(FETCH_SIZE)], fetch_offs, 2'b00};

	// 核心状态机，从总线获取读取数据，或写入数据 并返回
	assign transfer_done = busy_o & bus_resp_i.data_last & bus_resp_i.data_ok & bus_req_o.data_ok;
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
			default:begin
				fsm_state_next = fsm_state;
			end
		endcase
	end
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
		bus_req_o.write = '0;
		bus_req_o.burst = '0;
		bus_req_o.cached = '0;
		bus_req_o.addr = fetch_addr;

		bus_req_o.w_data = '0;
		bus_req_o.data_strobe = '0;
		bus_req_o.data_ok = fsm_state == STATE_DATA;
		bus_req_o.data_last = '0;
	end

	// 输出数据逻辑
	decoder decoder_module(
		.inst_i(bus_resp_i.r_data),
		.decode_info_o(decode_info_tmp),
		.inst_string_o(inst_string)
	);

	// 输出寄存逻辑
	always_ff @(posedge clk) begin : proc_decode_output_o
		if(~rst_n) begin
			decode_output_o <= 0;
		end else begin
			if(transfer_done) begin
				decode_output_o[fetch_offs] <= decode_info_tmp;
			end
		end
	end

endmodule