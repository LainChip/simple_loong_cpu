`include "common.svh"
`include "pipeline.svh"
`include "decoder.svh"

// 负责对指令寄存器数据进行转发
// 转发的来源已经在issue阶段完成解码，只需要按照解码结果进行转发即可。
module forwarding_unit#(
	parameter int DATA_WIDTH = 32,
	parameter int SOURCE_NUM = 3,
	parameter int PIPE_NUM = 2
)(
	input [$clog2(PIPE_NUM) - 1 : 0] pipe_sel_i,
	input [SOURCE_NUM : 0] sel_vec_i, // 0 for not forwarding
	input [PIPE_NUM - 1 : 0][SOURCE_NUM - 1: 0][DATA_WIDTH - 1 : 0] data_vec_i,
	input [DATA_WIDTH - 1 : 0] old_data_i,

	output logic[DATA_WIDTH - 1 : 0] new_data_o
);
	
	logic [SOURCE_NUM : 0][DATA_WIDTH - 1 : 0] data_src;
	assign data_src[0] = old_data_i;
	assign data_src[SOURCE_NUM : 1] = data_vec_i[pipe_sel_i];

	always_comb begin
		new_data_o = data_src[0] & {DATA_WIDTH{sel_vec_i[0]}};
		for (int i = 1; i <= SOURCE_NUM; i += 1) begin
			new_data_o |= data_src[i] & {DATA_WIDTH{sel_vec_i[i]}};
		end
	end

endmodule
