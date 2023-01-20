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

/* step() 
 * - time walk a step, and then signal do something under statement control 
 * 先前信号的时延 -> 时延后信号赋值(clk固定取反 + 自定义信号变化) -> 模型同步
 */
#define step(statements) do { \
        contextp->timeInc(1); \
        top->clk = !top->clk; \
            {statements}      \
        top->eval();          \
    } while (0)

struct DivRes {
    uint32_t q = 0;
    uint32_t s = 0;
};

void div_expRes(uint32_t z, uint32_t d, bool isSigned, DivRes& res) {
    if (d == 0) return;
    if (isSigned) {
        res.q = (int32_t)z / (int32_t)d;
        res.s = (int32_t)z % (int32_t)d;
    } else {
        res.q = z / d;
        res.s = z % d;
    }
}

bool is_equal(const std::unique_ptr<Vdivider>& top, const DivRes& exp) {
    if (top->D_i == 0) {
        return true;
    }
    if (top->q_o == exp.q && top->s_o == exp.s)
        return true;
    else return false;
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

    // init util variables
    DivRes expRes;
    std::default_random_engine e;
    std::uniform_int_distribution<uint32_t> gen_reg_fetch(0, UINT32_MAX);
    e.seed(time(0));

    // init signal
    top->rst_n = 0;
    top->clk = 0;
    top->eval();

    step();
    step({
        top->rst_n = 1; // 结束复位
    });
    step();
     
    // specific test
    std::cout << "[specific test]" << std::endl;
    //// case: input self data
    printf("== test selfdata ==\n");
    step({
        top->div_signed_i = 0;
        top->Z_i = 0x00001234;
        top->D_i = 0x00000000;
        top->div_valid = 1;
        top->res_ready = 1;
    });
    div_expRes(top->Z_i, top->D_i, top->div_signed_i, expRes);

    step();
    top->div_valid = 0;
    while (!(top->res_valid && top->res_ready)) {
        step();
    }

    if (!is_equal(top, expRes)) {
        printf("%08x, %08x, %d\n", top->Z_i, top->D_i, top->div_signed_i);
        printf("got   : %08x ... %08x\n", top->q_o, top->s_o);
        printf("expect: %08x ... %08x\n", expRes.q, expRes.s);
        step(); step();
        goto finished;
    } else {
        std::cout << "passed" << std::endl;
    }

    //// cases: res_ready = 0 from master, cannot receive
    printf("== test res_ready ==\n");
    step(); step();
    step({
        top->div_signed_i = 1;
        top->Z_i = gen_reg_fetch(e);
        top->D_i = gen_reg_fetch(e);
        top->div_valid = 1;
    });
    div_expRes(top->Z_i, top->D_i, top->div_signed_i, expRes);

    step();
    top->res_ready = 0; // master's res_ready not equipped
    top->div_valid = 0; 
    for (int i = 0; i < 16; ++i) {
        step();
    }
    step({
        top->res_ready = 1;
    });
    if (!is_equal(top, expRes)) {
        printf("%08x, %08x, %d\n", top->Z_i, top->D_i, top->div_signed_i);
        printf("got   : %08x ... %08x\n", top->q_o, top->s_o);
        printf("expect: %08x ... %08x\n", expRes.q, expRes.s);
        step(); step();
        goto finished;
    } else {
        std::cout << "passed" << std::endl;
    }


    puts("");

    // random test
    std::cout << "[random test]" << std::endl;
    
    for (int div_signed = 0; div_signed < 2; ++div_signed) {
        top->div_signed_i = div_signed;
        printf(div_signed ? "== test signed ==\n" : "== test unsigned ==\n");
        for (int i = 0; i < TEST_TIMES; ++i) {
            step({
                top->Z_i = gen_reg_fetch(e);
                top->D_i = gen_reg_fetch(e);
                top->div_valid = 1;
            });
            div_expRes(top->Z_i, top->D_i, top->div_signed_i, expRes);
            
            step();
            while (!(top->res_valid && top->res_ready)) {
                step();
            }

            if (!is_equal(top, expRes)) {
                printf("%08x, %08x, %d\n", top->Z_i, top->D_i, top->div_signed_i);
                printf("got   : %08x ... %08x\n", top->q_o, top->s_o);
                printf("expect: %08x ... %08x\n", expRes.q, expRes.s);
                step();step();
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
