// For std::unique_ptr
#include <memory>
#include <stdlib.h>
// Include common routines
#include <verilated.h>
#include "Vmulti_channel_fifo.h"

#include <algorithm>
#include <vector>

#include "verilated_vcd_c.h" //可选，如果要导出vcd则需要加上

// Legacy function required only so linking works on Cygwin and MSVC++
double sc_time_stamp() { return 0; }

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
    const std::unique_ptr<Vmulti_channel_fifo> top{new Vmulti_channel_fifo{contextp.get(), "TOP"}};

    // Set Vtop's input signals
    top->rst_n = 0;
    top->clk = 0;
    top->write_num_i = 0;
    top->read_num_i = 0;
    int cnt = 0;
    int r_cnt = 0;
    // Simulate until $finish
    while (!contextp->gotFinish() && contextp->time() < 1000000) {
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

        // Evaluate model
        // (If you have multiple models being simulated in the same
        // timestep then instead of eval(), call eval_step() on each, then
        // eval_end_step() on each. See the manual.)
        top->eval();

        if (contextp->time() > 10) {
            top->rst_n = 1;
        } else {
            top->rst_n = 0;
        }

        if (top->clk && top->rst_n) {
            if(contextp->time() % 10000 == 1) {
                printf("time: %d, cnt: %d,r_cnt: %d\n",contextp->time(),cnt,r_cnt);
            }
            top->write_valid_i = rand() & 1;
            top->read_ready_i = 0;
            if(top->write_ready_o && top->write_valid_i) {
                int random_write_num = rand() % 3;
                top->write_num_i = random_write_num;
                top->write_data_i = 0;
                for(int i = 0 ; i < random_write_num; i++) {
                    top->write_data_i |= ((long long)cnt) << (32 * i);
                    cnt++;
                }
            }
            if(top->read_valid_o) {
                top->read_ready_i = rand() & 1;
                if(top->read_ready_i) {
                    int random_read_num = top->read_valid_o == 0 ? 0 : (rand() % (top->read_valid_o > 1 ? 3 : 2));
                    top->read_num_i = random_read_num;
                    int err = 0;
                    for(int i = 0 ; i < random_read_num; i++) {
                        if(((top->read_data_o >> (i * 32)) & 0xffffffff) != r_cnt) {
                            printf("i:%d,top->read_data_o[0]: %d,top->read_data_o[1]: %d,r_cnt: %d\n",i,top->read_data_o & 0xffffffff,
                            (top->read_data_o >> (32)) & 0xffffffff, r_cnt);
                            err = 1;
                            // assert(0);
                        }
                        r_cnt ++;
                    }
                    if(err) {
                        break;
                    }
                }
            }
        }
        
    }
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
