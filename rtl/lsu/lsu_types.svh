`ifndef _LSU_TYPES_HEADER
`define _LSU_TYPES_HEADER

`include "common.svh"

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

typedef struct packed{
    // 响应信号
    logic ready;                               // 说明cache的请求被响应，响应后ready信号也应该被拉低

    // 数据
    logic data_ok;                             // 拉高时说明总线数据有效
    logic data_last;                           // 最后一个有效数据
    logic[`_CACHE_BUS_DATA_LEN - 1 : 0] r_data; // 总线返回的数据
}cache_bus_resp_t;

`endif