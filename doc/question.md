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

csrxchg 指令采用上述解码方式的设计考量。