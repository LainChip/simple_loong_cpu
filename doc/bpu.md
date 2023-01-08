# BPU设计文档

## 一、接口设计

| 接口名 | 方向   | 类型               | 作用                            |
| ------ | ------ | ------------------ | ------------------------------- |
| clk    | input  | logic              | 时钟                            |
| restn  | input  | logic              | 复位                            |
| stall  | input  | logic              | 暂停                            |
| update | input  | bpu_update_info_t  | bpu更新信号                     |
| bpinfo | output | bpu_predict_info_t | bpu的预测信息，用于生成更新信号 |
| pc     | output | [31:0]             | 下一次取指令的起始地址          |
| npc    | output | [31:0]             | bpu预测的下一次取指位置         |
| valid  | output | logic              | 标志pc有效，否则需要暂停pipe    |

- `bpu_update_info_t`

  ```
  ```

- `bpu_predict_info_t`

  ```
  
  ```

## 二、实现

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