# 分支指令解码doc

## 1、loongson-chiplab实现的精简的跳转指令

```verilog
wire inst_jirl; // 跳转链接指令，类似于mips的jarl
wire inst_b;      
wire inst_bl;     
wire inst_beq;    
wire inst_bne; 
wire inst_blt;
wire inst_bge;
wire inst_bltu;
wire inst_bgeu;
```

源代码链接：https://gitee.com/loongson-edu/chiplab/blob/chiplab_diff/IP/myCPU/id_stage.v

loong架构中`r1`寄存器充当返回地址寄存器

## 2、python脚本json

```json
{
    "const": {
        "_BRANCH_INVALID":   2'b0, // 非跳转指令
        "_BRANCH_IMMEDIATE": 2'b1, // 无条件立即数跳转或直接跳转
        "_BRANCH_INDIRECT"   2'b2, // 无条件间接跳转
        "_BRANCH_CONDITION"  2'b3  // 有条件跳转(目标地址均由imm决定)
    },
    
    "signal": {
       	"branch_type": {
            "length": 2,
            "stage": "ex",
            "default_value": 0,
            "invalid_value": 0
        }
    },
    
    "inst": {
        "jirl": {
            "opcode": "010011",
            "branch_type": "_BRANCH_INDIRECT",
            // TODO
        },
        "b": {
            "opcode": "010100",
            "branch_type": "_BRANCH_IMMEDIATE",
            // TODO
        },
        "bl": {
            "opcode": "010101",
            "branch_type": "_BRANCH_IMMEDIATE",
            // TODO
        },
        "beq": {
            "opcode": "010110",
            "branch_type": "_BRANCH_CONDITION",
            // TODO
        },
        "bne": {
            "opcode": "010111",
            "branch_type": "_BRANCH_CONDITION",
            // TODO
        },
        "blt": {
            "opcode": "011000",
            "branch_type": "_BRANCH_CONDITION",
            // TODO
        },
        "bge": {
            "opcode": "011001",
            "branch_type": "_BRANCH_CONDITION",
            // TODO
        },
        "bltu": {
            "opcode": "011010",
            "branch_type": "_BRANCH_CONDITION",
            // TODO
        },
        "bgeu": {
            "opcode": "011011",
            "branch_type": "_BRANCH_CONDITION",
            // TODO
        }
    }
}
```