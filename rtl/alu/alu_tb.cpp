// For std::unique_ptr
#include <memory>

// Include common routines
#include <verilated.h>

// Include model header, generated from Verilating "top.v"
#include "Valu_tester.h"

// 导出vcd
#include "verilated_vcd_c.h"

// 使用cpp
#include "alu_tb.h"
#include <iostream>
#include <climits>

// Legacy function required only so linking works on Cygwin and MSVC++
double sc_time_stamp() { return 0; }

int main(int argc, char** argv) {
    // Prevent unused variable warnings
    if (false && argc && argv) {}

    // Create logs/ directory in case we have traces to put under it
    Verilated::mkdir("logs");

    // Construct a VerilatedContext to hold simulation time, etc.
    // Multiple modules (made later below with Vtop) may share the same
    // context to share time, or modules may have different contexts if
    // they should be independent from each other.

    // Using unique_ptr is similar to
    // "VerilatedContext* contextp = new VerilatedContext" then deleting at end.
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    // Do not instead make Vtop as a file-scope static variable, as the
    // "C++ static initialization order fiasco" may cause a crash

    // Set debug level, 0 is off, 9 is highest presently used
    // May be overridden by commandArgs argument parsing
    contextp->debug(0);

    // Randomization reset policy
    // May be overridden by commandArgs argument parsing
    contextp->randReset(2);

    // Verilator must compute traced signals
    contextp->traceEverOn(true);

    // Pass arguments so Verilated code can see them, e.g. $value$plusargs
    // This needs to be called before you create any model
    contextp->commandArgs(argc, argv);

    // Construct the Verilated model, from Vtop.h generated from Verilating "top.v".
    // Using unique_ptr is similar to "Vtop* top = new Vtop" then deleting at end.
    // "TOP" will be the hierarchical name of the module.
    const std::unique_ptr<Valu_tester> top{new Valu_tester{contextp.get(), "TOP"}};

    // Set Vtop's input signals
    top->pc = 0x9f105380;
    top->reg_fetch0 = 0;
    top->reg_fetch1 = 0;
    top->ui5 = 0;
    top->si12 = 0;
    top->si20 = 0;
    uint32_t expRes;

    for (auto& inst : inst_seqs) {
        top->alu_type = inst.alu_type;
        top->opd_type = inst.opd_type;
        top->opd_unsigned = inst.opd_unsigned;

        std::cout << "testing " << inst.name << " ...\n";

        if (inst.opd_type == 0) {
            for (uint64_t i = 0; i < 1024; ++i) {
                //printf("%d\n", i);
                top->reg_fetch0 = (uint32_t)(i & 0xffffffff);
                top->reg_fetch1 = (uint32_t)(i >> 32) | 0x1;
                
                contextp->timeInc(1);
                top->eval();

                expRes = inst.expRes_r(top->reg_fetch0, top->reg_fetch1);
                if (top->alu_res != expRes) {
                    printf("%08x, %08x\n", top->reg_fetch0, top->reg_fetch1);
                    printf("got   : %08x\n", top->alu_res);
                    printf("expect: %08x\n", expRes);

                    contextp->timeInc(1);
                    top->eval();
                    goto finished;
                }
            }
        } else {
            for (uint32_t i = 0; i < ULONG_MAX; ++i) {
                top->reg_fetch0 = i;
                if (inst.name == "pcaddu12i") top->pc = i;
                for (uint32_t imm25_0 = 0; i < 0x04000000; ++i) {
                    // 与expRes_i不同，没有数的含义，仅取01串
                    top->ui5 = (imm25_0 >> 10) & 0x1f;                    
                    top->si12 = (imm25_0 >> 10) & 0xfff;
                    top->si20 = (imm25_0 >> 5) & 0x03ffffff;

                    contextp->timeInc(1);
                    top->eval();

                    expRes = inst.expRes_i(top->reg_fetch0, imm25_0);
                    if (top->alu_res != expRes) {
                        printf("%08x, %08x, %08x, %08x\n", top->reg_fetch0, top->ui5, top->si12, top->si20);
                        printf("got   : %08x\n", top->alu_res);
                        printf("expect: %08x\n", expRes);

                        contextp->timeInc(1);
                        top->eval();
                        goto finished;
                    }
                }
            }
        }
        
        std::cout << "pass " << inst.name << " ...\n\n";
    }
    finished:
    // Final model cleanup
    top->final();

    // Coverage analysis (calling write only after the test is known to pass)
#if VM_COVERAGE
    Verilated::mkdir("logs");
    contextp->coveragep()->write("logs/coverage.dat");
#endif

    // Return good completion status
    // Don't use exit() or destructor won't get called
    return 0;
}
