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
#include <random>
#include <ctime>

#define TEST_TIMES (10000)

#define next(top) do { \
        contextp->timeInc(1); \
        top->eval();          \
    } while (0)


// Legacy function required only so linking works on Cygwin and MSVC++
double sc_time_stamp() { return 0; }

void printStatus(std::unique_ptr<Valu_tester>& top) {
    printf("[reg_fetch]: %08x, %08x\n", top->reg_fetch0, top->reg_fetch1);
    printf("[imm25_0]: %08x; %08x, %08x, %08x\n", top->reg_fetch0, top->ui5, top->si12, top->si20);
}

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

    // util variables
    uint32_t expRes;
    uint32_t imm25_0;

    // specific test
    std::cout << "[specific test]" << std::endl;
    int ino = 12;
    top->alu_type = inst_seqs[ino].alu_type;
    top->opd_type = inst_seqs[ino].opd_type;
    top->opd_unsigned = inst_seqs[ino].opd_unsigned;
    top->pc = 0x9f105380;
    top->reg_fetch0 = 0x9f36bbc4;
    top->reg_fetch1 = 0xb586f1ae;
    top->ui5 = 0;
    top->si12 = 0;
    top->si20 = 0;

    next(top);

    expRes = inst_seqs[ino].expRes_r(top->reg_fetch0, top->reg_fetch1);
    if (top->alu_res != expRes) {
        printf("%08x, %08x\n", top->reg_fetch0, top->reg_fetch1);
        printf("got   : %08x\n", top->alu_res);
        printf("expect: %08x\n", expRes);
        
        next(top);
        top->final();
        #if VM_COVERAGE
            Verilated::mkdir("logs");
            contextp->coveragep()->write("logs/coverage.dat");
        #endif
        return 0;
    }
    std::cout << "passed" << std::endl << std::endl;

    // random test
    std::cout << "[random test]" << std::endl;
    std::default_random_engine e;
    std::uniform_int_distribution<uint32_t> gen_reg_fetch(0, ULONG_MAX);
    std::uniform_int_distribution<uint32_t> gen_imm25_0(0, 0x03ffffff);
    e.seed(time(0));

    for (auto& inst : inst_seqs) {
        top->alu_type = inst.alu_type;
        top->opd_type = inst.opd_type;
        top->opd_unsigned = inst.opd_unsigned;

        std::cout << "testing " << inst.name << " ...\n";

        if (inst.opd_type == 0) {
            for (uint64_t i = 0; i < TEST_TIMES; ++i) {
                //printf("%d\n", i);
                top->reg_fetch0 = gen_reg_fetch(e);
                top->reg_fetch1 = gen_reg_fetch(e);
                
                next(top);

                expRes = inst.expRes_r(top->reg_fetch0, top->reg_fetch1);
                if (top->alu_res != expRes) {
                    printf("%08x, %08x\n", top->reg_fetch0, top->reg_fetch1);
                    printf("got   : %08x\n", top->alu_res);
                    printf("expect: %08x\n", expRes);

                    next(top);
                    goto finished;
                }
            }
        } else {
            for (uint32_t i = 0; i < TEST_TIMES/20; ++i) {
                top->reg_fetch0 = gen_reg_fetch(e);
                if (inst.name == "pcaddu12i") top->pc = top->reg_fetch0;
                for (uint32_t j = 0; j < TEST_TIMES/20; ++j) {
                    imm25_0 = gen_imm25_0(e);
                    // 与expRes_i不同，没有数的含义，仅取01串
                    top->ui5 = (imm25_0 >> 10) & 0x1f;                    
                    top->si12 = (imm25_0 >> 10) & 0xfff;
                    top->si20 = (imm25_0 >> 5) & 0x000fffff;

                    next(top);

                    expRes = inst.expRes_i(top->reg_fetch0, imm25_0);
                    if (top->alu_res != expRes) {
                        printf("%08x, %08x, %08x, %08x\n", top->reg_fetch0, top->ui5, top->si12, top->si20);
                        printf("got   : %08x\n", top->alu_res);
                        printf("expect: %08x\n", expRes);

                        next(top);
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
