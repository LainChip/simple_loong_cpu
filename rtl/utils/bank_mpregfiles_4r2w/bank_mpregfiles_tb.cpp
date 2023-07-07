// For std::unique_ptr
#include <memory>

// Include common routines
#include <verilated.h>

// Include model header, generated from Verilating "top.v"
#include "Vbank_mpregfiles_4r2w.h"

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


// Legacy function required only so linking works on Cygwin and MSVC++
double sc_time_stamp() { return 0; }


int main(int argc, char** argv) {
    // Prevent unused variable warnings
    if (false && argc && argv) {}
    Verilated::mkdir("logs");

    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->debug(0);
    contextp->randReset(2);
    contextp->traceEverOn(true);
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<Vbank_mpregfiles_4r2w> top{new Vbank_mpregfiles_4r2w{contextp.get(), "TOP"}};

    /* Init signal */
    top->rst_n = 0;
    top->clk = 0;
    top->wa0_i = top->wa1_i = 15;
    top->we0_i = top->we1_i = 0;
    top->eval();
    /* Reset: clear regs */
    for (int i = 0; i < 32; ++i) {
        step();
    }
    /* round1: write all and than read all */
    printf("test round1: common...\n");
    // write all
    step({
        top->rst_n = 1;
    });
    uint32_t write_num = 0x87654321;
    for (int i = 0; i < 16; ++i) {
        step({
            top->we0_i = top->we1_i = 1;
            top->wa0_i = i*2;   top->wd0_i = write_num+i*2;
            top->wa1_i = i*2+1; top->wd1_i = write_num+i*2+1;
        });
        step();
    }
    // read all
    top->we0_i = top->we1_i = 0;
    for (int i = 0; i < 8; ++i) {
        step({
            top->ra0_i = i*4 + 0;
            top->ra1_i = i*4 + 1;
            top->ra2_i = i*4 + 2;
            top->ra3_i = i*4 + 3;
        });
        // check
        printf("get [%d]: %x\n", i*4+0, top->rd0_o);
        printf("get [%d]: %x\n", i*4+1, top->rd1_o);
        printf("get [%d]: %x\n", i*4+2, top->rd2_o);
        printf("get [%d]: %x\n", i*4+3, top->rd3_o);
        assert(top->rd0_o == (write_num + i*4 + 0));
        assert(top->rd1_o == (write_num + i*4 + 1));
        assert(top->rd2_o == (write_num + i*4 + 2));
        assert(top->rd3_o == (write_num + i*4 + 3));

        step();
    }
    printf("round1 pass!\n");
    step();
    step();

    /* round2: write conflict */
    printf("test round2: write conflict...\n");
    write_num = 0x12343210;
    for (int i = 0; i < 32; ++i) {
        step({
            top->we0_i = top->we1_i = 1;
            top->wa0_i = i; top->wd0_i = write_num+i*2;
            top->wa1_i = i; top->wd1_i = write_num+i*2+1;
        });
        step();
    }
    // read all
    top->we0_i = top->we1_i = 0;
    for (int i = 0; i < 8; ++i) {
        step({
            top->ra0_i = i*4 + 0;
            top->ra1_i = i*4 + 1;
            top->ra2_i = i*4 + 2;
            top->ra3_i = i*4 + 3;
        });
        // check
        printf("get [%d]: %x\n", i*4+0, top->rd0_o);
        printf("get [%d]: %x\n", i*4+1, top->rd1_o);
        printf("get [%d]: %x\n", i*4+2, top->rd2_o);
        printf("get [%d]: %x\n", i*4+3, top->rd3_o);
        assert(top->rd0_o == (write_num + i*8 + 0));
        assert(top->rd1_o == (write_num + i*8 + 3));
        assert(top->rd2_o == (write_num + i*8 + 4));
        assert(top->rd3_o == (write_num + i*8 + 7));

        step();
    }
    printf("round2 pass!\n");

    step();

    finished:
    // Final model cleanup
    top->final();

    // Coverage analysis (calling write only after the test is known to pass)
#if VM_COVERAGE
    Verilated::mkdir("logs");
    contextp->coveragep()->write("logs/coverage.dat");
#endif

    return 0;
}
