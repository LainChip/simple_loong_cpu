`include "common.svh"
`include "pipeline.svh"
`include "decoder.svh"

// 负责指令的发射控制，将指令送入后端管线执行
// 目前后端拥有两条管线，分别处理ALU/LSU/CSR/BRANCH 和 ALU
module issue(
		input logic clk,
		input logic rst_n,
		input inst_t [1:0] inst_i,
		input logic  [1:0] inst_valid_i,
		input logic [1:0][2:0] stall_vec_i,			// 0 for ex, 1 for m1, 2 for m2
		input logic [1:0][2:0] clr_vec_i,				// 0 for ex, 1 for m1, 2 for m2

		output logic  [1:0] issue_o, // 2'b00, 2'b01, 2'b11 三种情况，指令必须顺序发射.
		output logic revert_o,         // send inst[0] to pipe[1], inst[1] to pipe[0]. otherwise, inst[0] to pipe[0], inst[1] to pipe[1]
		output forwarding_info_t [1:0][1:0]forwarding_info_o,
		input  logic stall_i,
		input  logic clr_frontend_i
	);

	typedef struct packed{
		logic pipe_sel;				  // 为0时，指令在pipe 0， 否之在pipe 1 
		logic [2:0] inst_pos;         // 0 for ex, 1 for m1, 2 for m2, shifted to left  (0 -> 1 -> 2)
		logic [2:0] forwarding_ready; // 0 for ex, 1 for m1, 2 for m2, shifted to right (2 -> 1 -> 0)
	} scoreboard_info_t;

	/*
	TIME WREG (reg1)INST_POST (reg1)FORWARDING_READY
	 0   01	  ***             ***
	 1   !=01 3'b001          3'b111 ADD.W
	 2   **   3'b010          3'b011
	 3   **   3'b100          3'b001
	 4   **   3'b000          3'b000
	 5   01   3'b001          3'b100 LD.W
	 6   **   3'b010          3'b010
	 7   **   3'b100          3'b001
	 8   **   3'b000          3'b000

	*/
	function forwarding_info_t get_forwarding_info(
		input scoreboard_info_t scoreboard_entry
	);
		forwarding_info_t ret;
		
		// ex gen
		ret.ex_forward_source[3:1] = scoreboard_entry.inst_pos[2:0] & {3{scoreboard_entry.forwarding_ready[0]}};
		ret.ex_forward_source[0] = ~|ret.ex_forward_source[3:1];
		// m1 gen
		ret.m1_forward_source[2:1] = scoreboard_entry.inst_pos[1:0] & {2{scoreboard_entry.forwarding_ready[1]}};
		ret.m1_forward_source[0] = ~|ret.m1_forward_source[2:1];
		// m2 gen
		ret.m2_forward_source[1] = scoreboard_entry.inst_pos[0:0] & {1{scoreboard_entry.forwarding_ready[2]}};
		ret.m2_forward_source[0] = ~ret.m2_forward_source[1];
		
		return ret;

	endfunction
	
	// Conflict 函数返回一时，表明不可发射，存在冲突
	function logic raw_conflict(
		input scoreboard_info_t [31:0] scoreboard,
		input inst_t inst
	);
		bit ret;
		scoreboard_info_t [1:0] scoreboard_entry;
		scoreboard_entry[0] = scoreboard[inst.register_info.r_reg[0]];
		scoreboard_entry[1] = scoreboard[inst.register_info.r_reg[1]];
		ret = '0;
		for(integer i = 0 ; i < 2; i += 1) begin
			if(inst.decode_info.is.use_time[i] == `_USE_EX) begin
				ret |= ~((scoreboard_entry[i].inst_pos == '0) || (scoreboard_entry[i].forwarding_ready[0]));
			end else /*if(inst.decode_info.is.use_time[i] == `_USE_M2)*/begin
				ret |= ~((scoreboard_entry[i].inst_pos == '0) || (scoreboard_entry[i].forwarding_ready));
			end
		end
		return ret;
	endfunction

	// 当第二条指令写回寄存器地址与第一条指令写回寄存器地址相同且不为0时，不可以发射。
	// 当第二条指令的读寄存器地址与第一条指令写回寄存器地址相同且不为0时，不可以发射。
	// 这个操作解除了两条同时发射指令之间的数据相关性，可以将两条指令的顺序进行任意处理（注意异常，跳转时候的特殊处理）
	// 对于所有中断，两条指令被同时处理。 
	function logic second_inst_data_conflict(
		input inst_t inst_first,
		input inst_t inst_second
	);
		if(inst_first.register_info.w_reg == '0) begin
			return 1'b0;
		end else begin
			if(inst_first.register_info.w_reg == inst_second.register_info.r_reg[0] || 
			   inst_first.register_info.w_reg == inst_second.register_info.r_reg[1] || 
			   inst_first.register_info.w_reg == inst_second.register_info.w_reg ) 
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
		input inst_t inst_first,
		input inst_t inst_second
	);
		return inst_first.decode_info.is.pipe_one_inst & inst_second.decode_info.is.pipe_one_inst;
	endfunction

	// 对于计分板的更新，输入中包含有对于每一级的暂停向量，以及跳转clr向量。
	// 如果成功发射的指令操作本计分板项目，按照成功发射的指令信息更新计分板
	// 对于暂停向量使能的流水线级，更新暂停，否之，执行一次更新
	// 对于清零向量使能的流水线级，清空之前记录的信息，设置最保险的配置（不可转发，指令位于之后一级流水）。
	// 暂停向量优先级高于清零向量，以避免意外的 跳转/异常
	// 成功发射与暂停互斥，不可能同时发生
	// 成功发射与清零可以同时发射，但成功发射优先。
	function scoreboard_info_t scoreboard_update(
		input inst_t [1:0] inst,
		input logic  [1:0] issue,
		input logic [1:0][2:0] stall_vec,			// 0 for ex, 1 for m1, 2 for m2
		input logic [1:0][2:0] clr_vec,				// 0 for ex, 1 for m1, 2 for m2
		input scoreboard_info_t old_scoreboard_entry,
		input integer entry_id
	);
		scoreboard_info_t ret;
		if(entry_id == 0) begin
			return '0;
		end
		// 正常更新逻辑 优先级最低
		ret.pipe_sel = old_scoreboard_entry.pipe_sel;
		ret.inst_pos = {old_scoreboard_entry.inst_pos[1:0],1'b0};
		ret.forwarding_ready = {1'b0,old_scoreboard_entry.forwarding_ready[2:1]};
		// 清零更新逻辑
		if(old_scoreboard_entry.inst_pos & clr_vec[old_scoreboard_entry.pipe_sel]) begin
			ret.inst_pos = {old_scoreboard_entry.inst_pos[1:0],1'b0};
			ret.forwarding_ready = '0;
		end
		// 暂停更新逻辑
		if(old_scoreboard_entry.inst_pos & stall_vec[old_scoreboard_entry.pipe_sel]) begin
			ret.inst_pos = old_scoreboard_entry.inst_pos;
			ret.forwarding_ready = old_scoreboard_entry.forwarding_ready;
		end

		// 发射更新逻辑 优先级最高
		for(integer i = 0 ; i < 2 ; i += 1) begin
			if((inst[i].register_info.w_reg == entry_id) && issue[i]) begin
				ret.pipe_sel = i;
				ret.inst_pos = 3'b001;
				ret.forwarding_ready = {1'b1,inst[i].decode_info.is.ready_time == `_READY_EX,inst[i].decode_info.is.ready_time == `_READY_EX};
			end
		end
		return ret;
	endfunction

	// 计分板
	scoreboard_info_t[31:0] scoreboard;

	// 分别判断两条指令可否发射
	logic issue_first_inst;
	assign issue_first_inst = inst_valid_i[0] & ~raw_conflict(scoreboard, inst_i[0])
	& ~stall_i & ~clr_frontend_i;
	logic issue_second_inst;
	assign issue_second_inst = issue_first_inst & inst_valid_i[1]
	& (~raw_conflict(scoreboard, inst_i[1])) 
	& (~second_inst_data_conflict(inst_i[0], inst_i[1]))
	& (~second_inst_control_conflict(inst_i[0], inst_i[1]))
	& ~stall_i & ~clr_frontend_i;

	assign issue_o = {issue_second_inst, issue_first_inst};
	assign revert_o = (issue_second_inst & inst_i[1].decode_info.is.pipe_one_inst) | (issue_first_inst & inst_i[0].decode_info.is.pipe_two_inst);

	// 处理两条指令的forwarding 控制信息
	for(genvar i = 0 ; i < 2 ; i+=1) begin
		for(genvar j = 0 ; j < 2 ; j+=1) begin
			assign forwarding_info_o[i][j] = get_forwarding_info(scoreboard[inst_i[i].register_info.r_reg[j]]);
		end
	end

	// 计分板更新
	generate
		for(genvar i = 0 ; i < 32; i+=1) begin
			always_ff @(posedge clk) begin : proc_scoreboard
				if(~rst_n) begin
					scoreboard[i] <= '0;
				end else begin
					scoreboard[i] <= scoreboard_update(inst_i,issue_o,stall_vec_i,clr_vec_i,scoreboard[i],i);
				end
			end
		end
	endgenerate

endmodule
