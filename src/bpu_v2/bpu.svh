// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : bpu.svh
// Create : 2023-01-30 17:37:20
// Revise : 2023-02-02 11:04:00
// Editor : sublime text4, tab size (4)
// Brief  : 
// -----------------------------------------------------------------------------

`ifndef _BPU_SVH_
`define _BPU_SVH_

`define _STRONGLY_TAKEN 2'b11
`define _WEAKLY_TAKEN 2'b10
`define _WEAKLY_NOT_TAKEN 2'b01
`define _STRONGLY_NOT_TAKEN 2'b00

`define _STRONGLY_GLOBAL 2'b11
`define _WEAKLY_GLOBAL 2'b10
`define _WEAKLY_LOCAL 2'b01
`define _STRONGLY_LOCAL 2'b00

// scale
`define _BLOCK_SIZE 2 // 保证 2 ** k == `_BLOCK_SIZE (k = 0, 1, 2, ...), k取决于cache的取指个数
`define _BTB_ADDR_WIDTH 10
`define _LPHT_ADDR_WIDTH 10
`define _RAS_STACK_DEPTH 8
`define _BHT_ADDR_WIDTH 5
`define _BHT_DATA_WIDTH 3
`define _GHR_DATA_WIDTH 10

// br_type
`define _PC_RELATIVE 2'b00
`define _ABSOLUTE 2'b01
`define _CALL 2'b10
`define _RETURN 2'b11


// bpu interface
typedef struct packed {
	logic flush;
	logic br_taken;
	logic [31:0] pc;
	logic [31:0] br_target;
	
	// for btb
	logic btb_update;
	logic [1:0] br_type;

	// for bht
	logic bht_update;

	// for lpht
	logic lpht_update;
	logic [1:0] lphr;
	logic [`_LPHT_ADDR_WIDTH - 1:0] lphr_index;

	// for ghr
	logic [`_GHR_DATA_WIDTH - 1:0] ghr_checkpoint;
} bpu_update_t;


typedef struct packed {
	logic taken;
	logic [$clog2(`_BLOCK_SIZE) - 1:0] choice;
	logic [31:0] npc;
	logic [1:0] lphr;
	logic [`_LPHT_ADDR_WIDTH - 1:0] lphr_index;
} bpu_predict_t;

`endif // _BPU_SVH_
