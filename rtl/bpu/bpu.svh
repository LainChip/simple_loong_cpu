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


`define _BTB_ADDR_WIDTH 10

`define _PHT_ADDR_WIDTH 10

`define _RAS_WRITE_GUARD "OFF"
`define _RAS_STACK_WIDTH 8

// Br_type
`define _PC_RELATIVE 2'b00
`define _ABSOLUTE 2'b01
`define _CALL 2'b10
`define _RETURN 2'b11 


// bpu interface
typedef struct packed {
	logic taken;
	logic [31:0] target;
	// TODO
} bpu_update_info_t;


typedef struct packed {
	logic [31:0] npc;
	// TODO
} bpu_predict_info_t;

`endif // _BPU_SVH_