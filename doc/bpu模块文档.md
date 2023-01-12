# BPU设计文档

## 一、模块定义

| 接口名    | 方向   | 类型           | 作用                            |
| --------- | ------ | -------------- | ------------------------------- |
| clk       | input  | logic          | 时钟                            |
| rst_n     | input  | logic          | 复位                            |
| stall_i   | input  | logic          | 暂停                            |
| update_i  | input  | bpu_feedback_t | bpu更新信号                     |
| predict_o | output | bpu_predict_t  | bpu的预测信息，用于生成更新信号 |
| pc_o      | output | [31:0]         | 下一次取指令的起始地址          |
| stall_o   | output | logic          | 分支预测器refill，pipe需要暂停  |
| valid_o   | output | [1:0]          | 标记有效指令                    |

## 二、模块行为描述

- 分支预测

## 三、模块新增类型

- `bpu_feedback_t`

  ```systemverilog
  
  ```

- `bpu_predict_t`

  ```systemverilog
  
  ```

## 四、模块时序说明

- TODO

## 五、模块实现

### 1、BPU

- 顶层模块
- 由于BTB和PHT存储相邻两行的预测信息，所以只需要采用$PC[31:3]$进行预测，用$PC[2]$来判断预测信息是否有效

### 1、BTB

- 由于实际的程序中大多数情况两条分支指令不相邻，故一个BTB行存储相邻两条指令的预测信息，这两条指令的pc满足
	$$
	PC\_0[2] == 0\quad and \quad PC\_1[2] == 1
	$$

- BTB由于规模的关系，有一个周期的延迟

- tag的生成

	```systemverilog
	function logic[15:0] mktag(logic[31:2] pc);
		return {pc[31:17] ^ pc[16:2], pc[2]};
	endfunction
	```

	$PC[2]$作为tag的最后一位用来严格的校验是相邻指令中的哪一条