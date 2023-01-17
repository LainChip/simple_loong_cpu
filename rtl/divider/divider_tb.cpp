// For std::unique_ptr
#include <memory>

// Include common routines
#include <verilated.h>

// Include model header, generated from Verilating "top.v"
#include "Vdivider.h"

// 导出vcd
#include "verilated_vcd_c.h"

// 使用cpp
#include <iostream>
#include <climits>
#include <random>
#include <ctime>

#define TEST_TIMES (10000)

#define next(top) do { \
        contextp->timeInc(1); \
        top->eval();          \
    } while (0)

struct DivRes {
    uint32_t q = 0;
    uint32_t s = 0;
};

void div_expRes(uint32_t z, uint32_t d, bool isSigned, DivRes& res) {
    if (isSigned) {
        res.q = (int32_t)z / (int32_t)d;
        res.s = (int32_t)z % (int32_t)d;
    } else {
        res.q = z / d;
        res.s = z % d;
    }
}

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
    const std::unique_ptr<Vdivider> top{new Vdivider{contextp.get(), "TOP"}};

    // util variables
    DivRes expRes;

    // specific test
    std::cout << "[specific test]" << std::endl;
    top->div_signed_i = 0;
    top->Z_i = 0x2905ea84;
    top->D_i = 0x04474f4a;
    next(top);
    div_expRes(top->Z_i, top->D_i, top->div_signed_i, expRes);
    if (top->q_o != expRes.q || top->s_o != expRes.s) {
        printf("%08x, %08x, %d\n", top->Z_i, top->D_i, top->div_signed_i);
        printf("got   : %08x ... %08x\n", top->q_o, top->s_o);
        printf("expect: %08x ... %08x\n", expRes.q, expRes.s);
        next(top);
    } else {
        std::cout << "passed" << std::endl << std::endl;
    }

    puts("");

    // random test
    std::cout << "[random test]" << std::endl;
    std::default_random_engine e;
    std::uniform_int_distribution<uint32_t> gen_reg_fetch(0, UINT32_MAX);
    e.seed(time(0));

    for (int div_signed = 0; div_signed < 2; ++div_signed) {
        top->div_signed_i = div_signed;
        printf(div_signed ? "== test signed ==\n" : "== test unsigned ==\n");
        for (int i = 0; i < TEST_TIMES; ++i) {
            top->Z_i = gen_reg_fetch(e);
            top->D_i = gen_reg_fetch(e);
            next(top);
            div_expRes(top->Z_i, top->D_i, top->div_signed_i, expRes);
            if (top->q_o != expRes.q || top->s_o != expRes.s) {
                printf("%08x, %08x, %d\n", top->Z_i, top->D_i, top->div_signed_i);
                printf("got   : %08x ... %08x\n", top->q_o, top->s_o);
                printf("expect: %08x ... %08x\n", expRes.q, expRes.s);
                next(top);
                goto finished;
            }
        }
        std::cout << "pass\n";
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
