# arbiter_round_robin模块文档

arbiter_round_robin是一个使用经典round robin算法的公平仲裁器。

对于所有的公平arbiter仲裁器，输入输出接口定义都是一致的，

外部模块会输入可配置数量个的请求，在arbiter内部做出选择后，输出被选择的信号。

外部同时还会与请求传入一个take_sel_i信号，说明该请求被采纳，arbiter应该做出相应状态转化。


## 模块定义

此模块比较简单，不会额外产生任何的控制结构体

```systemverilog
module arbiter_round_robin #(
	parameter int REQ_NUM = 4
	)(
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input take_sel_i,                       // 输出会被采纳
	input  logic[REQ_NUM - 1 : 0] req_i,    // REQ_NUM组输入的有效信号
	output logic[REQ_NUM - 1 : 0] sel_o     // REQ_NUM组输入中，被采纳的一组输入，独热码编码
);
```

## 模块行为描述

该模块是一个对round_robin仲裁算法的硬件实现，每一轮次仲裁中，上一轮次被选择的信号，在下一轮次会成为调度优先级最低的信号，对于其他信号也会进行方便的调整。

在初始时，req_i中的最高位有最大的优先级。

## 模块新增类型
无


## 模块时序说明

对于所有信号有效的情况，round robin会从最高位开始循环选择所有信号

~~~json
{
    signal: [
    {name: 'clk',        wave: 'p.......'},
    {name: 'req_i',      wave: '2.......', data:['1111']},
    {name: 'take_sel_i', wave: '01.01...'},
    {name: 'sel_o',      wave: '2.22.222', data:['1000','0100','0010','0001','1000','0100']}
    ]
}
~~~

![image-20230106130529761](..\..\..\new_cpu\pic\image-4.png)
