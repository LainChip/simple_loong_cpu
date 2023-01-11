// For std::unique_ptr
#include <memory>
#include <stdlib.h>
// Include common routines
#include <verilated.h>
#include "Vlsu_test_plantform.h"

#include <algorithm>
#include <vector>

#include "verilated_vcd_c.h" //可选，如果要导出vcd则需要加上

// Legacy function required only so linking works on Cygwin and MSVC++
double sc_time_stamp() { return 0; }

const int test_num = 1024 * 32; // In word.
int valid_data[4 * 1024];

int random_addr(int index, int seed)
{
    static std::vector<int> temp;
    if(temp.size() == 0) {
        for(int i = 0 ; i < test_num; i++){
            int high_bit = rand() << 14;
            temp.push_back(i | high_bit);
        }
        std::random_shuffle(temp.begin(),temp.end());
    }
    return temp[(index + seed) % test_num];
}

int random_data(int index, int seed)
{
    static std::vector<int> temp;
    if(temp.size() == 0) {
        for(int i = 0 ; i < test_num; i++){
            temp.push_back(rand());
        }
        std::random_shuffle(temp.begin(),temp.end());
    }
    return temp[(index + seed) % test_num];
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
    const std::unique_ptr<Vlsu_test_plantform> top{new Vlsu_test_plantform{contextp.get(), "TOP"}};

    // Set Vtop's input signals
    top->rst_n = 0;
    top->clk = 0;
    int cnt = 0;
    int read = 0;
    // Simulate until $finish
    while (!contextp->gotFinish()) {
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

        // Read outputs
        int read_addr = random_addr(cnt - 2,read?(test_num / 2) : 0) << 2;
        int read_data = valid_data[(read_addr>>2) & 0xfff];
        // printf("time:%ld,read:%d,read_data:0x%x,addr:0x%x,stall:%d\n",contextp->time(),read,top->r_data,cnt - 2,top->pipe_stall);
        
        if(top->rst_n && !top->pipe_stall && !top->clk) {   
            if(read && cnt > 2) {
                // printf("time:%ld,read:%d,read_data:0x%x,addr:0x%x,cnt:%d.stall:%d\n",contextp->time(),read,top->r_data,read_addr,cnt - 2,top->pipe_stall);
                assert(top->r_data == read_data);
            }
            cnt++;
        }

        if (top->clk) {
            if (contextp->time() > 10) {
                top->rst_n = 1;
            } else {
                top->rst_n = 0;
            }
            // Assign some other inputs
            if(cnt < test_num) {
                // Do write or read
                top->write = !read;
                top->way_sel = rand() & 1;
                top->stall_req = rand() & 1;
                top->w_data = rand();
                top->addr = random_addr(cnt,read?(test_num / 2) : 0) << 2;
                if(!read)
                    valid_data[(random_addr(cnt,read?(test_num / 2) : 0)) & 0xfff] = top->w_data;
            } else {
                if(read) {
                    break;
                } else {
                    read = 1;
                    cnt = 0;
                }
            }
        }
        
        // printf("time:%ld,req:%04d,take:%d,sel:%04d\n",contextp->time(),get_binary(top->req_i),top->take_sel_i,get_binary(top->sel_o));
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
