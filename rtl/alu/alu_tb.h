#ifndef _ALU_TB_H_
#define _ALU_TB_H_

#define _NIL  (0)
#define _ADD  (1)
#define _SUB  (2)
#define _SLT  (3)
#define _AND  (4)
#define _OR   (5)
#define _XOR  (6)
#define _NOR  (7)
#define _SL   (8)
#define _SR   (9)
#define _MUL  (10)
#define _MULH (11)    
#define _DIV  (12)
#define _MOD  (13)
#define _LUI  (14)

#define _IMM_U5  (0b001)
#define _IMM_S12 (0b010)
#define _IMM_U12 (0b011)
#define _IMM_S20 (0b100)

#include <map>
#include <string>
#include <vector>

using namespace std;

struct InstSeq {
    int no;
    string name;
    u_char alu_type;
    u_char opd_type;
    u_char opd_unsigned;

    InstSeq(int no, string n, u_char at, u_char ot, u_char ou):
    no(no), name(n), alu_type(at), opd_type(ot), opd_unsigned(ou) {}

    uint32_t expRes_r(uint32_t a, uint32_t b) {
        if (name == "add.w") {
            return a + b;
        } else if (name == "sub.w"  ) {
            return a - b;
        } else if (name == "slt"    ) {
            return ((int)a < (int)b) ? 1 : 0;
        } else if (name == "sltu"   ) {
            return (a < b) ? 1 : 0;
        } else if (name == "nor"    ) {
            return ~(a | b);
        } else if (name == "and"    ) {
            return a & b;
        } else if (name == "or"     ) {
            return a | b;
        } else if (name == "xor"    ) {
            return a ^ b;
        } else if (name == "sll.w"  ) {
            return a << (b & 0x1f);
        } else if (name == "srl.w"  ) {
            return a >> (b & 0x1f);
        } else if (name == "sra.w"  ) {
            return (int32_t)a >> (b & 0x1f);
        } else if (name == "mul.w"  ) {
            return (int32_t)a * (int32_t)b;
        } else if (name == "mulh.w" ) {
            // 显示转换仅会在高位补0!
            int64_t a64 = (int64_t)a << 32 >> 32;
            int64_t b64 = (int64_t)b << 32 >> 32;
            return (a64 * b64) >> 32;   // 强转自动截取后32位
        } else if (name == "mulh.wu") {
            return ((int64_t)a * (int64_t)b) >> 32;
        } else if (name == "div.w"  ) {
            return (int32_t)a / (int32_t)b;
        } else if (name == "mod.w"  ) {
            return (int32_t)a % (int32_t)b;
        } else if (name == "div.wu" ) {
            return a / b;
        } else if (name == "mod.wu" ) {
            return a % b;
        }       
        return -1;          
    }

    uint32_t expRes_i(uint32_t a, uint32_t imm25_0) {
        uint32_t ui5 = (imm25_0 >> 10) & 0x1f;

        int32_t tmp = (imm25_0 << 10) & 0xfff00000; // 要取的12位从最高位开始
        uint32_t si12 = (int32_t)tmp >> 20;
        uint32_t ui12 = (uint32_t)tmp >> 20;

        uint32_t si20 = (imm25_0 << 7) & 0xfffff000;
        if (name == "slli.w") {
            return a << ui5;
        } else if (name == "srli.w") {
            return a >> ui5;
        } else if (name == "srai.w") {
            return (int32_t)a >> ui5;
        } else if (name == "slti"  ) {
            return ((int32_t)a < (int32_t)si12) ? 1 : 0; 
        } else if (name == "sltui" ) {
            return (a < si12) ? 1 : 0;
        } else if (name == "addi.w") {
            return a + si12;
        } else if (name == "andi.w") {
            return a & ui12;
        } else if (name == "ori.w" ) {
            return a | ui12;
        } else if (name == "xori.w") {
            return a ^ ui12;
        } else if (name == "lu12i.w") {
            return si20;
        } else if (name == "pcaddu12i") {
            return a + si20;    // pc
        }
    }

    string toString() {
        return "[" + name + "] " + to_string(alu_type) + " " + to_string(opd_type) + " " + to_string(opd_unsigned) + ": ";
    }
};

vector<InstSeq> inst_seqs = {
    InstSeq(0 , "add.w"  , _ADD , 0, 0),
    InstSeq(1 , "sub.w"  , _SUB , 0, 0),
    InstSeq(2 , "slt"    , _SLT , 0, 0),
    InstSeq(3 , "sltu"   , _SLT , 0, 1),
    InstSeq(4 , "nor"    , _NOR , 0, 0),
    InstSeq(5 , "and"    , _AND , 0, 0),
    InstSeq(6 , "or"     , _OR  , 0, 0),
    InstSeq(7 , "xor"    , _XOR , 0, 0),
    InstSeq(8 , "sll.w"  , _SL  , 0, 0),
    InstSeq(9 , "srl.w"  , _SR  , 0, 1),
    InstSeq(10, "sra.w"  , _SR  , 0, 0),
    InstSeq(11, "mul.w"  , _MUL , 0, 0),
    InstSeq(12, "mulh.w" , _MULH, 0, 0),
    InstSeq(13, "mulh.wu", _MULH, 0, 1),
    InstSeq(14, "div.w"  , _DIV , 0, 0),
    InstSeq(15, "mod.w"  , _MOD , 0, 0),
    InstSeq(16, "div.wu" , _DIV , 0, 1),
    InstSeq(17, "mod.wu" , _MOD , 0, 1),
    InstSeq(18, "slli.w" , _SL  , _IMM_U5, 0),
    InstSeq(19, "srli.w" , _SR  , _IMM_U5, 1),
    InstSeq(20, "srai.w" , _SR  , _IMM_U5, 0),
    InstSeq(21, "slti"   , _SLT , _IMM_S12, 0),
    InstSeq(22, "sltui"  , _SLT , _IMM_S12, 1),
    InstSeq(23, "addi.w" , _ADD , _IMM_S12, 0),
    InstSeq(24, "andi.w" , _AND , _IMM_U12, 0),
    InstSeq(25, "ori.w"  , _OR  , _IMM_U12, 0),
    InstSeq(26, "xori.w" , _XOR , _IMM_U12, 0),
    InstSeq(27, "lu12i.w"  , _LUI, _IMM_S20, 0),
    InstSeq(28, "pcaddu12i", _ADD, _IMM_S20, 0),
};

map<int, string> aluType2Name = {
    { 0 , "NIL"  },
    { 1 , "ADD"  },
    { 2 , "SUB"  },
    { 3 , "SLT"  },
    { 4 , "AND"  },
    { 5 , "OR"   },
    { 6 , "XOR"  },
    { 7 , "NOR"  },
    { 8 , "SL"   },
    { 9 , "SR"   },
    { 10, "MUL"  },    
    { 11, "MULH" },    
    { 12, "DIV"  },    
    { 13, "MOD"  },    
    { 14, "LUI"  },    
};

#endif