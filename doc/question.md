## 问题

1. Linux主线中是否支持Loongarch32r指令集，若不存在，那么有无计划将对la32r的支持合入主线，或者提供支持smp的la32r内核版本？
2. （不是问题）精简指令集 p12 MULH.WU少打U 
3.  文档中似乎没有明确tlb修改（fill wr inv）操作 cacheop操作后如何消除管线中的冒险（类似MIPS中ehb，eret有清除execution hazard的功能，tlb操作或者cache操作之后要求有barrier去消除冒险）。
