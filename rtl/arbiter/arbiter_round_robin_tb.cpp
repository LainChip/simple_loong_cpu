// For std::unique_ptr
#include <memory>
#include <stdlib.h>
// Include common routines
#include <verilated.h>
#include "Varbiter_round_robin.h"

 
#include "verilated_vcd_c.h" //可选，如果要导出vcd则需要加上

// Legacy function required only so linking works on Cygwin and MSVC++
double sc_time_stamp() { return 0; }

int get_binary(int input) {
    return ((input & 0x8) / 0x8) * 1000 + ((input & 0x4) / 0x4) * 100 +((input & 0x2) / 0x2) * 10 +((input & 0x1) / 0x1) * 1;
}

int main(int argc, char **argv, char **env)
{
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
    const std::unique_ptr<Varbiter_round_robin> top{new Varbiter_round_robin{contextp.get(), "TOP"}};

    // Set Vtop's input signals
    top->rst_n = 0;
    top->clk = 0;
    top->req_i = 0;
    top->take_sel_i = 0;
    int cnt[4] = {0,0,0,0};

    // Simulate until $finish
    while (!contextp->gotFinish() && contextp->time() < 100000) {
        // Historical note, before Verilator 4.200 Verilated::gotFinish()
        // was used above in place of contextp->gotFinish().
        // Most of the contextp-> calls can use Verilated:: calls instead;
        // the Verilated:: versions just assume there's a single context
        // being used (per thread).  It's faster and clearer to use the
        // newer contextp-> versions.

        contextp->timeInc(1);  // 1 timeprecision period passes...
        // Historical note, before Verilator 4.200 a sc_time_stamp()
        // function was required instead of using timeInc.  Once timeInc()
        // is called (with non-zero), the Verilated libraries assume the
        // new API, and sc_time_stamp() will no longer work.

        // Toggle a fast (time/2 period) clock
        top->clk = !top->clk;

        // Toggle control signals on an edge that doesn't correspond
        // to where the controls are sampled; in this example we do
        // this only on a negedge of clk, because we know
        // reset is not sampled there.
        if (!top->clk) {
            if (contextp->time() > 1) {
                top->rst_n = 1;
                top->take_sel_i = 1;
            } else {
                top->rst_n = 0;
                top->take_sel_i = 0;
            }
            // Assign some other inputs
            top->req_i = (rand() & 0x1) | ((rand() & 0x1) << 1) |  ((rand() & 0x1) << 2) |  ((rand() & 0x1) << 3);
            // top->req_i = 0xf;
        }

        // Evaluate model
        // (If you have multiple models being simulated in the same
        // timestep then instead of eval(), call eval_step() on each, then
        // eval_end_step() on each. See the manual.)
        top->eval();

        // Read outputs
        assert(((~top->req_i) & top->sel_o) == 0);
        for(int i = 0 ; i < 4 ; i++) {
            cnt[i] += (top->sel_o & (1 << i)) ? 1 : 0;
        }
        // printf("time:%ld,req:%04d,take:%d,sel:%04d\n",contextp->time(),get_binary(top->req_i),top->take_sel_i,get_binary(top->sel_o));
    }
    printf("final: %d,%d,%d,%d",cnt[0],cnt[1],cnt[2],cnt[3]);
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
