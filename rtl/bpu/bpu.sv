// -----------------------------------------------------------------------------
// Copyright (c) 2014-2023 All rights reserved
// -----------------------------------------------------------------------------
// Author : Jiuxi 2506806016@qq.com
// File   : bpu.sv
// Create : 2023-01-07 22:13:44
// Revise : 2023-01-10 20:39:22
// Editor : sublime text4, tab size (4)
// -----------------------------------------------------------------------------

`include "bpu.svh"

module bpu (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input stall_i,
	input bpu_update_t update_i,
	output bpu_predict_t [1:0] predict_o,
	output reg [31:0] pc_o,
	output stall_o
);

	

endmodule : bpu