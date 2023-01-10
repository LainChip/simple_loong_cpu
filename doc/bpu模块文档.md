# BPU设计文档

## 一、模块定义

| 接口名   | 方向   | 类型               | 作用                            |
| -------- | ------ | ------------------ | ------------------------------- |
| clk      | input  | logic              | 时钟                            |
| rst_n    | input  | logic              | 复位                            |
| stall_i  | input  | logic              | 暂停                            |
| update_i | input  | bpu_update_info_t  | bpu更新信号                     |
| bpinfo_o | output | bpu_predict_info_t | bpu的预测信息，用于生成更新信号 |
| pc_o     | output | [31:0]             | 下一次取指令的起始地址          |
| stall_o  | output | logic              | 分支预测器refill，pipe需要暂停  |
| valid_o  | output | [1:0]              | 标记有效指令                    |

## 二、模块行为描述

- 分支预测

## 三、模块新增类型

- `bpu_update_info_t`

  ```
  
  ```

- `bpu_update_info_t`

  ```
  
  ```

## 四、模块时序说明

- TODO

## 五、模块实现

### 1、BTB

- 由于实际的程序中大多数情况两条分支指令不相邻，故一个BTB行存储相邻两条指令的预测信息，这两条指令的pc满足
	$$
	PC\_0[2] == 0\quad and \quad PC\_1[2] == 1
	$$

- BTB由于规模的关系，有一个周期的延迟