`include "common.svh"

module issue(
		input inst_t [1:0] inst_i,
		input  logic  [1:0] inst_valid_i,
		output logic  [1:0] issue_num, // 0, 1, 2
		input  logic stall_i
	);

	typedef struct packed{
		logic forwarding_pipe_sel;		// 为0时，选择pipe 0 作为转发源， 否之选择pipe 1 作为转发源头
		logic [2:0] ex_forward_source;	// 0 for m1, 1 for m2, 2 for wb
		logic [1:0] m1_forward_source;  // 0 for m2, 1 for wb
		logic [0:0] m2_forward_source;  // 0 for wb
	} forwarding_info_t;
	typedef struct packed{
		logic [1:0][4:0] r_reg; // 0 for rk, 1 for rj
		logic [4:0] w_reg;
	} register_info_t;

	typedef struct packed{
		logic pipe_sel;				  // 为0时，指令在pipe 0， 否之在pipe 1
		logic [2:0] inst_pos;         // 0 for ex, 1 for m1, 2 for m2, shifted to left
		logic [2:0] forwarding_ready; //
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
	
endmodule