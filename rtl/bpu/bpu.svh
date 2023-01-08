`ifndef _BPU_SVH_
`define _BPU_SVH_

`define STRONGLY_TAKEN 2'b11
`define WEAKLY_TAKEN 2'b10
`define WEAKLY_NOT_TAKEN 2'b01
`define STRONGLY_NOT_TAKEN 2'b00

`define STRONGLY_GLOBAL 2'b11
`define WEAKLY_GLOBAL 2'b10
`define WEAKLY_LOCAL 2'b01
`define STRONGLY_LOCAL 2'b00


`define BTB_ADDR_WIDTH 10












// Br_type
`define PC_RELATIVE 2'b00
`define ABSOLUTE 2'b01
`define CALL 2'b10
`define RETURN 2'b11 








`endif // _BPU_SVH_