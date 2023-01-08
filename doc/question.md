## TODO：

### src/inst/csr.json

#### 空缺信号：

syscall、ertn、break、idle是否需要统一命名

#### csrxchg/csrrd/csrwr指令opcode问题：

csrrd: rj域为0
csrwr: rj域为1
csrxchg: rj域不为0或1时，表示寄存器号

json如何填写

## 问题

1. 在Linux主线中是否存在对于Loongarch32r的支持，若不存在，那么有无计划将对la32r的支持合入主线，或者提供支持smp的la32r内核版本？
2. csrxchg 指令采用上述解码方式的设计考量。
