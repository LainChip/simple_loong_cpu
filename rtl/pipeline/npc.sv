`include "pipeline.svh"

function logic[`_BHT_ADDR_WIDTH - 1 : 0] get_bht_addr(logic[31:0]va);
  return va[`_BHT_ADDR_WIDTH + 1 : 2] ^ va[`_BHT_ADDR_WIDTH + `_BHT_ADDR_WIDTH + 1 : `_BHT_ADDR_WIDTH + 2];
endfunction
function logic[`_LPHT_ADDR_WIDTH - 1 : 0] get_lpht_addr(logic[`_BHT_DATA_WIDTH - 1 : 0] bht,logic[31:0]va);
  return 
endfunction
module npc(
    input logic clk,
    input logic rst,

    input logic rst_jmp,
    input logic[31:0] rst_target,

    output logic[1:0][31:0] pc_o,
    output logic[1:0] valid_o, // 2'b00 | 2'b01 | 2'b11

    output bpu_predict_t predict_o,
    input bpu_correct_t correct_i
  );

  logic[31:0] ppc, ppcplus4, pc;
  // 使用 ppc 输入 bram 得到下周期的预测依据
  typedef struct {
            logic[31:2] target_pc;
            logic[`_TAG_ADDR_WIDTH  - 1 : 0 ] tag;
            logic dir_type;
            logic branch_type;
          }btb_t;
  btb_t btb_q;
  logic[1:0] lpht;
  logic[`_BHT_ADDR_WIDTH - 1 : 0] bht_addr_q;
  logic[`_BHT_DATA_WIDTH - 1 : 0] bht_data;
  logic[`_LPHT_ADDR_WIDTH - 1 : 0] lpht_addr;
  logic [`_RAS_ADDR_WIDTH - 1: 0] ras_ptr_q,ras_ptr;

  // 本周期 pc 对应的预测依据
  logic predict_dir_type_q;
  logic predict_dir_jmp;
  logic [1:0] predict_target_type_q;
  logic [31:0] ras_target_q,btb_target,npc_target;
  always_comb begin
    predict_dir_type_q = btb_q.dir_type;
    predict_target_type_q = btb_q.branch_type;
    predict_dir_jmp = |lpht[1];
  end

  // ppc 逻辑
  always_comb begin
    if(rst_jmp) begin
      ppc = rst_target;
    end
    else begin
      if(predict_dir_type_q) begin
        if(predict_dir_jmp) begin
          ppc = btb_target;
        end
      end
      else begin
        if(predict_target_type_q == `_BPU_TARGET_NPC) begin
          ppc = npc_target;
        end
        else if(predict_target_type_q == `_BPU_TARGET_RETURN) begin
          ppc = ras_target_q;
        end
        else begin
          ppc = btb_target;
        end
      end
    end
  end

  // ras_ptr 逻辑
  always_comb begin

  end

  // ppcplus4 逻辑
  assign ppcplus4 = ppc + 32'd4;

  // btb 生成
  simpleDualPortRamRE # (
                        .dataWidth(),
                        .ramSize(),
                        .latency(1),
                        .readMuler(1)
                      )
                      btb_table (
                        .clk(clk),
                        .rst_n(rst_n),
                        .addressA(addressA),
                        .we(we),
                        .addressB(addressB),
                        .re(re),
                        .inData(inData),
                        .outData(outData)
                      );
  // bht, lpht 生成
  simpleDualPortLutRam # (
                         .dataWidth(`_BHT_DATA_WIDTH),
                         .ramSize((1 << `_LPHT_ADDR_WIDTH)),
                         .latency(0),
                         .readMuler(1)
                       )
                       bht_table (
                         .clk(clk),
                         .rst_n(rst_n),
                         .addressA(),
                         .we(),
                         .addressB(bht_addr_q),
                         .re(1'b1),
                         .inData(),
                         .outData(lpht_addr)
                       );
  simpleDualPortLutRam # (
                         .dataWidth(2),
                         .ramSize((1 << `_LPHT_ADDR_WIDTH)),
                         .latency(0),
                         .readMuler(1)
                       )
                       lpht_table (
                         .clk(clk),
                         .rst_n(rst_n),
                         .addressA(),
                         .we(),
                         .addressB(lpht_addr),
                         .re(1'b1),
                         .inData(),
                         .outData(lpht)
                       );
endmodule
