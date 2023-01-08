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

### (一)方向预测

#### 1、局部预测

- lpht
- TODO
- 分支预测的主力

#### 2、全局预测

- gpht
- TODO
- 从经验上看，gpht无需规模过大，大部分分支与全局无关

#### 3、竞争预测

- cpht

### (二)目标地址预测

#### 1、直接跳转

- btb
- TODO

#### 2、间接跳转

- 在我们实现loong架构指令集中理论上只有CALL/RETURN的`jirl`指令属于此类型
- ras
- 计划添加ras的出错恢复
- TODO