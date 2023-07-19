`ifndef _PIPELINE_HEADER
`define _PIPELINE_HEADER

`include "decoder.svh"

        // TODO
        typedef logic priv_resp_t;
typedef logic priv_req_t;

// 解码出来的寄存器信息
typedef struct packed{
          logic [1:0][4:0] r_reg; // 0 for rk, 1 for rj
          logic [4:0] w_reg;
        } reg_info_t;

// 发射后的寄存器信息
typedef struct packed{
          logic [1:0][4:0] r_addr;
          logic [1:0][3:0] r_id;
          logic [1:0] r_ready;
        } read_flow_t;
typedef struct packed{
          logic [4:0] w_addr;
          logic [2:0] w_id;
          logic w_valid;
        } write_flow_t;
// 控制流，目前未进行精简。
typedef struct packed {
          logic valid_inst;  // 标记指令是否有效（包含推测执行 / 确定执行） ::: 需要被 rst clr
          logic need_commit; // 标记指令是否可提交，在 M2 级才是确定值     ::: 需要被 rst clr && 被跳转信号 clr
        } exc_flow_t;

// 异常流
typedef struct packed {
          logic adef;
          logic tlbr;
          logic pif;
          logic ppi;
        } fetch_excp_t;
typedef struct packed {
          logic adem;
          logic ale;

          // FRONTEND
          logic adef;
          logic itlbr;
          logic pif;
          logic ippi;
        } excp_flow_t;

// 输入到后端的指令流
typedef struct packed {
          is_t decode_info;
          reg_info_t reg_info;
          bpu_into_t bpu_predict;
          fetch_excp_t fetch_excp;
          logic[31:0] pc;
        } inst_t;

typedef struct packed{
          ex_t decode_info;  // 指令控制信息 ::: 不需要 rst clr | 跳转 clr
          logic[4:0] w_reg;
          logic[2:0] w_id;
          bpu_predict_t bpu_predict;
          fetch_excp_t fetch_excp;
          logic[25:0] addr_imm;
          logic[31:0] pc;
        } pipeline_ctrl_ex_t; // 移位寄存器实现的部分

typedef struct packed{
          m1_t decode_info;  // 指令控制信息 ::: 不需要 rst clr | 跳转 clr
          bpu_predict_t bpu_predict;
          excp_flow_t excp_flow;
          logic[13:0] csr_id;
          logic[31:0] jump_target;
          logic[31:0] vaddr;
          logic[31:0] pc;
        } pipeline_ctrl_m1_t; // 移位寄存器实现的部分

typedef struct packed{
          m2_t decode_info;  // 指令控制信息 ::: 不需要 rst clr | 跳转 clr
          logic[31:0] vaddr;
          logic[31:0] paddr;
          logic[31:0] pc;
        } pipeline_ctrl_m2_t; // 移位寄存器实现的部分

typedef struct packed{
          wb_t decode_info;  // 指令控制信息 ::: 不需要 rst clr | 跳转 clr
          logic[31:0] pc;
        } pipeline_ctrl_wb_t; // 移位寄存器实现的部分

typedef struct packed{
          read_flow_t r_flow;
          logic[1:0][31:0] r_data;
        } pipeline_data_t; // 无法使用移位寄存器实现，普通寄存器

typedef struct packed{
          write_flow_t w_flow;
          logic[31:0] w_data;
        } pipeline_wdata_t;

typedef struct packed {
          logic [31:0] data;  // reg data
          logic [2 :0] id;    // reg addr
          logic valid;        // whether data is valid
        } fwd_data_t;
typedef struct packed {
          logic[1:0] inst_valid;
          inst_t[1:0] inst;
        }frontend_req_t;
typedef struct packed {
          logic[1:0] issue;
        }frontend_resp_t;

typedef struct packed {
          logic [31:0]    crmd;
          logic [31:0]    prmd;
          logic [31:0]    euen;
          logic [31:0]    ectl;
          logic [31:0]    estat;
          logic [31:0]    era;
          logic [31:0]    badv;
          logic [31:0]    eentry;
          logic [31:0]    tlbidx;
          logic [31:0]    tlbehi;
          logic [31:0]    tlbelo0;
          logic [31:0]    tlbelo1;
          logic [31:0]    asid;
          logic [31:0]    pgdl;
          logic [31:0]    pgdh;
          logic [31:0]    cpuid;
          logic [31:0]    save0;
          logic [31:0]    save1;
          logic [31:0]    save2;
          logic [31:0]    save3;
          logic [31:0]    tid;
          logic [31:0]    tcfg;
          logic [31:0]    tval;
          logic [31:0]    cntc;
          logic [31:0]    ticlr;
          logic [31:2]    llbctl;
          logic llbit;
          logic [31:0]    tlbrentry;
          logic [31:0]    ctag;
          logic [31:0]    dmw0;
          logic [31:0]    dmw1;
        }csr_t;

`endif
