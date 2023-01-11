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
    string name;
    u_char alu_type;
    u_char opd_type;
    u_char opd_unsigned;

    InstSeq(string n, u_char at, u_char ot, u_char ou):
    name(n), alu_type(at), opd_type(ot), opd_unsigned(ou) {}

    string toString() {
        return "[" + name + "] " + to_string(alu_type) + " " + to_string(opd_type) + " " + to_string(opd_unsigned) + ": ";
    }
};

vector<InstSeq> inst_seqs = {
    InstSeq("add.w"  , _ADD, 0, 0),
    InstSeq("sub.w"  , _SUB, 0, 0),
    InstSeq("slt"    , _SLT, 0, 0),
    InstSeq("sltu"   , _SLT, 0, 1),
    InstSeq("nor"    , _NOR, 0, 0),
    InstSeq("and"    , _AND, 0, 0),
    InstSeq("or"     , _OR , 0, 0),
    InstSeq("xor"    , _XOR, 0, 0),
    InstSeq("sll.w"  , _SL , 0, 0),
    InstSeq("srl.w"  , _SR , 0, 1),
    InstSeq("sra.w"  , _SR , 0, 0),
    InstSeq("mul.w"  , _MUL, 0, 0),
    InstSeq("mulh.w" , _MUL, 0, 0),
    InstSeq("mulh.wu", _MUL, 0, 0),
    InstSeq("div.w"  , _DIV, 0, 0),
    InstSeq("mod.w"  , _MOD, 0, 0),
    InstSeq("div.wu" , _DIV, 0, 1),
    InstSeq("mod.wu" , _MOD, 0, 1),
    InstSeq("slli.w" , _SL , _IMM_U5, 0),
    InstSeq("srli.w" , _SR , _IMM_U5, 1),
    InstSeq("srai.w" , _SR , _IMM_U5, 0),
    InstSeq("slti"   , _SLT, _IMM_S12, 0),
    InstSeq("sltui"  , _SLT, _IMM_S12, 1),
    InstSeq("addi.w" , _ADD, _IMM_S12, 0),
    InstSeq("andi.w" , _AND, _IMM_U12, 0),
    InstSeq("ori.w"  , _OR , _IMM_U12, 0),
    InstSeq("xori.w" , _XOR, _IMM_U12, 0),
    InstSeq("lu12i.w"  , _LUI, _IMM_S20, 0),
    InstSeq("pcaddu12i", _ADD, _IMM_S20, 0),
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