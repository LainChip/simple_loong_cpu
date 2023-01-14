`include "common.svh"
`include "pipeline.svh"
`include "decoder.svh"

// 负责指令的发射控制，将指令送入后端管线执行
// 目前后端拥有两条管线，分别处理ALU/LSU/CSR/BRANCH 和 ALU
module issue(
		input inst_t [1:0] inst_i,
		input  logic  [1:0] inst_valid_i,
		output logic  [1:0] issue_o, // 2'b00, 2'b01, 2'b11 三种情况，指令必须顺序发射.
		output logic revert_o,         // send inst[0] to pipe[1], inst[1] to pipe[0]. otherwise, inst[0] to pipe[0], inst[1] to pipe[1]
		input  logic stall_i
	);

	typedef struct packed{
		logic pipe_sel;				  // 为0时，指令在pipe 0， 否之在pipe 1
		logic [2:0] inst_pos;         // 0 for ex, 1 for m1, 2 for m2, shifted to left  (0 -> 1 -> 2)
		logic [2:0] forwarding_ready; // 0 for ex, 1 for m1, 2 for m2, shifted to right (2 -> 1 -> 0)
	} scoreboard_info_t;

	function forwarding_info_t (
			input scoreboard_info_t scoreboard_entry
	);
		forwarding_info_t ret;
		
		// ex gen
		ret.ex_forward_source = scoreboard_entry.inst_pos[2:0] & {3{scoreboard_entry.forwarding_ready[0]}};

		// m1 gen
		ret.m1_forward_source = scoreboard_entry.inst_pos[1:0] & {2{scoreboard_entry.forwarding_ready[1]}};
		
		// m2 gen
		ret.m2_forward_source = scoreboard_entry.inst_pos[0:0] & {1{scoreboard_entry.forwarding_ready[2]}};

	endfunction

	// 这个function应该放在前端，在fetch阶段和写入fifo阶段之间，合成inst_t的阶段进行。
	function register_info_t get_register_info(
		input decode_info_t decode_info
	);
		register_info_t ret;
		case(decode_info.is.reg_type)
			`_REG_TYPE_RW:begin
				ret.r_reg[0] = '0;
				ret.r_reg[1] = decode_info.general.inst25_0[9:5];
				ret.w_reg = decode_info.general.inst25_0[4:0];
			end
			`_REG_TYPE_RRW:begin
				ret.r_reg[0] = decode_info.general.inst25_0[14:10];
				ret.r_reg[1] = decode_info.general.inst25_0[9:5];
				ret.w_reg = decode_info.general.inst25_0[4:0];
			end
			// `_REG_TYPE_IRW:begin // 废弃的类型
			// 	ret.r_reg[0] = '0;
			// 	ret.r_reg[1] = decode_info.general.inst25_0[9:5];
			// 	ret.w_reg = decode_info.general.inst25_0[4:0];
			// end
			// `_REG_TYPE_IW:begin // 废弃的类型
			// 	ret.r_reg[0] = '0;
			// 	ret.r_reg[1] = '0;
			// 	ret.w_reg = '0;
			// end
			`_REG_TYPE_I:begin
				ret.r_reg[0] = '0;
				ret.r_reg[1] = '0;
				ret.w_reg = '0;
			end
			`_REG_TYPE_BL:begin
				ret.r_reg[0] = '0;
				ret.r_reg[1] = '0;
				ret.w_reg = 5'd1;
			end
			`_REG_TYPE_RR:begin
				ret.r_reg[0] = decode_info.general.inst25_0[4:0];
				ret.r_reg[1] = decode_info.general.inst25_0[9:5];
				ret.w_reg = '0;
			end
			`_REG_TYPE_CSRXCHG:begin
				ret.r_reg[0] = decode_info.general.inst25_0[4:0];
				ret.r_reg[1] = '0;
				ret.w_reg = decode_info.general.inst25_0[4:0];
			end
			`_REG_TYPE_RDCNTID:begin
				ret.r_reg[0] = '0;
				ret.r_reg[1] = '0;
				ret.w_reg = decode_info.general.inst25_0[9:5];
			end
			// `_REG_TYPE_R:begin
			// 	ret.r_reg[0] = '0;
			// 	ret.r_reg[1] = '0;
			// 	ret.w_reg = '0;
			// end
			default:begin
				ret.r_reg[0] = '0;
				ret.r_reg[1] = '0;
				ret.w_reg = '0;
			end
		endcase
	endfunction
	
	// Conflict 函数返回一时，表明不可发射，存在冲突
	function logic raw_conflict(
		input scoreboard_info_t [31:0] scoreboard,
		input inst_t inst
	);
		scoreboard_info_t [1:0] scoreboard_entry;
		scoreboard_entry[0] = scoreboard[inst.register_info.r_reg[0]];
		scoreboard_entry[1] = scoreboard[inst.register_info.r_reg[1]];
		logic [1:0] use_time; // `_USE_EX for use in ex, `_USE_M2 for use in m2
		use_time = inst.is.use_time;
		logic ret;
		ret = '0;
		for(integer i = 0 ; i < 2; i += 1) begin
			if(use_time[i] == `_USE_EX)
				ret |= ~((scoreboard_entry[i].inst_pos == '0) || (scoreboard_entry[i].forwarding_ready[0]));
			end else /*if(use_time[i] == `_USE_M2)*/begin
				ret |= ~((scoreboard_entry[i].inst_pos == '0) || (scoreboard_entry[i].forwarding_ready));
			end
		return ret;
	endfunction

	// 当第二条指令写回寄存器地址与第一条指令写回寄存器地址相同且不为0时，不可以发射。
	// 当第二条指令的读寄存器地址与第一条指令写回寄存器地址相同且不为0时，不可以发射。
	// 这个操作解除了两条同时发射指令之间的数据相关性，可以将两条指令的顺序进行任意处理（注意异常，跳转时候的特殊处理）
	// 对于所有中断，两条指令被同时处理。 
	function logic second_inst_data_conflict(
		input inst_t inst_fisrt,
		input inst_t inst_second
	);
		if(inst_fisrt.register_info.w_reg == '0) begin
			return 1'b0;
		end else begin
			if(inst_fisrt.register_info.w_reg == inst_second.register_info.r_reg[0] || 
			   inst_fisrt.register_info.w_reg == inst_second.register_info.r_reg[1] || 
			   inst_fisrt.register_info.w_reg == inst_second.register_info.w_reg ) 
			begin
				return 1'b1;
			end
		end
	endfunction

	// 对于两条指令发生控制冲突的情况进行处理
	// 两条指令中只能有一条为 分支/特权（包括所有会触发例外的指令）/存取
	// 两条指令中，只能有一条为计算-乘法 / 计算-除法指令。 所有的乘除法会被指派到第二条管线（目前），
	// 后续可能安排第三条管线处理多周期指令 （乘法/除法/浮点）。
	function logic second_inst_control_conflict(
		input inst_t inst_fisrt,
		input inst_t inst_second
	);
	endfunction

endmodule