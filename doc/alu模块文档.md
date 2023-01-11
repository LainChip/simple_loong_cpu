# alu模块文档

算术逻辑单元

## 模块定义

与往常alu不同，将所有信号均传入alu后再进行自行处理

```systemverilog
module alu #(
    parameter int GRLEN = 32    // 指令集中的参数，其实32位就是32，多余
    )(
    input  decode_info_t decode_info_i, // 解码所得信息
    input   [1:0][31:0] reg_fetch_i,    // 从regfile读出的寄存器操作数数据
    input   [31:0] pc_i,                // 当前pc值，为pcaddu12i指令服务
    output  [31:0] alu_res_o            // alu结果
);
```


## 模块行为描述
对于所有运算指令，单周期内计算并产出结果;

为方便tb，除0或模0时将返回-1


## 模块时序说明
全模块为组合逻辑电路，为求简单乘除法先直接使用systemerilog的运算符；当周期输入当周期输出