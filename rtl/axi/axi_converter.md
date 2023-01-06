# axi_converter模块文档

axi_converter是一个将处理器内部总线协议转换为外部axi-master接口的模块。

按照计划来说，axi_converter 将会是本处理器核心工程中，唯一涉及到外部axi接口的模块。



该模块支持内部产生的cache，uncached，burst，single传输请求，对外产生相同的axi请求并等待返回。



## 模块定义

注：

该模块会使用第三方开源代码，及接口

```systemverilog
module axi_converter#(
    parameter int CACHE_PORT_NUM = 2
)(
    input clk,input rst_n,
	AXI_BUS.Master   axi_bus, // 来自pulp_axi 库
    input cache_bus_req_t  [CACHE_PORT_NUM - 1 : 0]req_i,       // cache的访问请求
    output cache_bus_resp_t [CACHE_PORT_NUM - 1 : 0]resp_o      // cache的访问应答
);
```

## 模块行为描述

将一个或者多个cache内部bus类型连接到此转换模块，此模块整合成一个公共的axi_bus，连接到核外axi总线上。
该模块不会支持cache的一致性维护，故对于一致性维护，需要另外设计模块进行管理。

axi交互部分按照axi标准实现，基本要求为支持读写接口的五个通道，不对axi错误进行处理，扩展要求要对axi错误进行处理，向处理器cache部分进行错误的屏蔽或者汇报（总线错误中断）。

## 模块新增类型

### cache_bus_req_t
该类型是一个结构体，描述了cache的访问请求：
```systemverilog
typedef struct packed{
    // 请求信号
    logic valid;                             // 拉高时说明cache的请求有效，请求有效后，valid信号应该被拉低
    logic write;                             // 拉高时说明cache请求进行写入
    logic burst;                             // 0 for no burst, 1 for cache burst length
    logic cached;                            // 0 for uncached, 1 for cached
    logic[31:0] addr;                        // cache请求的物理地址

    // 数据
    logic data_ok;                           // 写入时，此信号用于说明cache已准备好提供数据。 读取时，此信号说明cache已准备好接受数据。
    logic data_lest;                         // 拉高时标记最后一个元素，只有读到此信号才认为传输事务结束
    logic[`_CACHE_BUS_DATA_LEN - 1:0] w_data; // cache请求的写数据
}cache_bus_req_t;
```

### cache_bus_resp_t
该类型是一个结构体，描述了cache的访问回应：
```systemverilog
typedef struct packed{
    // 响应信号
    logic ready;                               // 说明cache的请求被响应，响应后ready信号也应该被拉低

    // 数据
    logic data_ok;                             // 拉高时说明总线数据有效
    logic data_last;                           // 最后一个有效数据
    logic[`_CACHE_BUS_DATA_LEN - 1 : 0] r_data; // 总线返回的数据
}cache_bus_resp_t;
```



## 模块握手时序说明

整体请求与响应握手

```json
{
    signal: [
    {name: 'clk',        wave: 'p.|......'},
    {name: 'req.valid',  wave: '01|.0....'},
    {name: 'resp.ready', wave: '0.|10....'}
    ]
}
```

![image-20230105205715322](..\..\pic\image-20230105205323130.png)



数据握手，整体类似axi的握手过程

对于写数据

```json
{
    signal: [
    {name: 'clk',            wave: 'p|....|'},
    {name: 'req.w_data',     wave: 'x|.222|..2x',data:['data1','data2','data3','data4']},
    {name: 'req.data_ok',    wave: '0|.1..|...0'},
    {name: 'resp.data_ok',   wave: '0|1..0|.1.0'},
    {name: 'req.data_last',  wave: '0|....|..10'},
    ]
}
```

![image-20230105211120212](..\..\pic\image-20230105211035713.png)



对于读数据，情况也是类似的
