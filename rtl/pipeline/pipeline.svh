`ifndef _PIPELINE_HEADER
`define _PIPELINE_HEADER

`include "decoder.svh"
`include "bpu.svh"

// 由issue逻辑产生的转发信号组
typedef struct packed{
	logic forwarding_pipe_sel;		// 为0时，选择pipe 0 作为转发源， 否之选择pipe 1 作为转发源头
	logic [3:0] ex_forward_source;	// 0 for nof, 1 for m1, 2 for m2, 3 for wb
	logic [2:0] m1_forward_source;  // 0 for nof, 1 for m2, 2 for wb
	logic [1:0] m2_forward_source;  // 0 for nof, 1 for wb
} forwarding_info_t;

// 解码出来的寄存器信息
typedef struct packed{
	logic [1:0][4:0] r_reg; // 0 for rk, 1 for rj
	logic [4:0] w_reg;
} register_info_t;

// 输入到后端的指令流信息
typedef struct packed {
	decode_info_t decode_info;
	register_info_t register_info;
	bpu_predict_t bpu_predict;
	logic[31:0] pc;
} inst_t;

// 控制流，目前未进行精简。 对于管线二，可以精简M1 M2部分。
typedef struct packed {
	decode_info_t decode_info;
	forwarding_info_t [1:0] forwarding_info;
	bpu_predict_t bpu_predict;
} ctrl_flow_t;

// 管线中的数据flow类型，目前未进行精简。 对于管线二，可以精简其寄存器部分。
typedef struct packed {
	logic[31:0] pc;
	logic[1:0][31:0] reg_data;
	logic[31:0] result;
} data_flow_t;

`endif