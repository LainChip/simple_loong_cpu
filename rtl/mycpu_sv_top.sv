`include "common.svh"

module core_top_sv(
    input           aclk,
    input           aresetn,
    input    [ 7:0] intrpt, 
    //AXI interface 
    //read reqest
    output   [ 3:0] arid,
    output   [31:0] araddr,
    output   [ 7:0] arlen,
    output   [ 2:0] arsize,
    output   [ 1:0] arburst,
    output   [ 1:0] arlock,
    output   [ 3:0] arcache,
    output   [ 2:0] arprot,
    output          arvalid,
    input           arready,
    //read back
    input    [ 3:0] rid,
    input    [31:0] rdata,
    input    [ 1:0] rresp,
    input           rlast,
    input           rvalid,
    output          rready,
    //write request
    output   [ 3:0] awid,
    output   [31:0] awaddr,
    output   [ 7:0] awlen,
    output   [ 2:0] awsize,
    output   [ 1:0] awburst,
    output   [ 1:0] awlock,
    output   [ 3:0] awcache,
    output   [ 2:0] awprot,
    output          awvalid,
    input           awready,
    //write data
    output   [ 3:0] wid,
    output   [31:0] wdata,
    output   [ 3:0] wstrb,
    output          wlast,
    output          wvalid,
    input           wready,
    //write back
    input    [ 3:0] bid,
    input    [ 1:0] bresp,
    input           bvalid,
    output          bready,

    output [31:0] debug0_wb_pc,
    output [ 3:0] debug0_wb_rf_wen,
    output [ 4:0] debug0_wb_rf_wnum,
    output [31:0] debug0_wb_rf_wdata,
    output [31:0] debug0_wb_inst
);

    assign debug0_wb_pc = '0;
    assign debug0_wb_rf_wen = '0;
    assign debug0_wb_rf_wnum = '0;
    assign debug0_wb_rf_wdata = '0;
    assign debug0_wb_inst = '0;

    AXI_BUS #(.AXI_ADDR_WIDTH(32),
		.AXI_ID_WIDTH  (4),
		.AXI_USER_WIDTH(1),
		.AXI_DATA_WIDTH(32)
    ) mem_bus;

    assign mem_bus.Master.aw_ready = awready;
    assign mem_bus.Master.w_ready = wready;
    assign mem_bus.Master.b_id = bid;
    assign mem_bus.Master.b_resp = bresp;
    assign mem_bus.Master.b.user = '0;
    assign mem_bus.Master.b_valid = bvalid;
    assign mem_bus.Master.ar_ready = arready;
    assign mem_bus.Master.r_id = rid;
    assign mem_bus.Master.r_data = rdata;
    assign mem_bus.Master.r_resp = rresp;
    assign mem_bus.Master.r_last = rlast;
    assign mem_bus.Master.r_user = '0;
    assign mem_bus.Master.r_valid = rvalid;

    assign awid = mem_bus.Master.aw_id;
    assign awaddr = mem_bus.Master.aw_addr;
    assign awlen = mem_bus.Master.aw_len;
    assign awsize = mem_bus.Master.aw_size;
    assign awburst = mem_bus.Master.aw_burst;
    assign awlock = mem_bus.Master.aw_lock;
    assign awcache = mem_bus.Master.aw_cache;
    assign awprot = mem_bus.Master.aw_prot;
    assign awvalid = mem_bus.Master.aw_valid;
    assign wdata = mem_bus.Master.w_data;
    assign wstrb = mem_bus.Master.w_strb;
    assign wlast = mem_bus.Master.w_last;
    assign wvalid = mem_bus.Master.w_valid;
    assign bready = mem_bus.Master.b_ready;
    assign arid = mem_bus.Master.ar_id;
    assign araddr = mem_bus.Master.ar_addr;
    assign arlen = mem_bus.Master.ar_len;
    assign arsize = mem_bus.Master.ar_size;
    assign arlock = mem_bus.Master.ar_lock;
    assign arcache = mem_bus.Master.ar_cache;
    assign arprot = mem_bus.Master.ar_prot;
    assign arvalid = mem_bus.Master.ar_valid;
    assign rready = mem_bus.Master.r_ready;

    logic rst_n;
    always_ff @(posedge aclk) begin
       rst_n <= aresetn;
    end

    cpu_core core(
      .clk(aclk),
      .rst_n(rst_n),
      .int_i(intrpt),
      .mem_bus(mem_bus)
    );

endmodule