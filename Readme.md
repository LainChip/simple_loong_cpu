## 目录结构

* ./src： 存放所有非rtl的辅助代码

* ./rtl： 存放所有的rtl代码，verilog/systemverilog
* ./doc：存放所有的文档，每个人负责的每个顶层模块都需要有相关文档，描述接口功能及时序或者组合功能。

* ./hw：硬件相关单元



## 代码相关

1. 使用systemVerilog作为rtl部分开发语言，除了顶层使用.v之外，其余层全部使用systemVerilog

2. 对于文档中描述的模块，可以拥有多种实现便于迭代开发。早期实现为了尽快跑起来，使用最简单的版本，后续实现在保证功能与前序简单版本一致的同时，加入新功能。对于模块的选择和替换，应该使用宏进行控制，相关的控制宏应该加入顶层通用config header。

3. 出于2中的原因，不要删除历史版本的rtl代码，使用宏ifdef 在多个版本中进行快速的切换。如果文档中的接口发生变更，同样需要对历史版本进行修正，如果时间上不允许，至少需要对最简单的原始版本进行相关修正，保证其他同学可以尽量不受此模块的bug影响完成快速调试。

   ```systemverilog
   // file: config.svh
   ...
   `define _I_CACHE_VER_2
   ...
   /*---------*/
   
   // file: i_cache_ver_1.sv
   `ifdef _I_CACHE_VER_1
   module i_cache();
       ...
   endmodule
   `endif
   /*---------*/
   
   // file: i_cache_ver_2.sv
   `ifdef _I_CACHE_VER_2
   module i_cache();
       ...
   endmodule
   `endif
   /*---------*/
   
   ```

   

4. 编写代码应尽量保证参数化，减少写死的部分，以提高可重用性。可以使用参数替代常数的地方，尽量使用参数，可以使用generate for结构的地方，尽量使用generate for。

5. 模块的接口应从少，从简，多使用struct进行包装，相关struct需要定义在头文件中

6. 一个systemVerilog文件唯一对应一个模块，每一个systemVerilog头部使用注释表明作者和完成时间，修改记录。修改版本号按本地的顺序从1开始每次增加1的进行标注，若发生合并冲突，则使用.1 .2 .m分别标注版本

   ~~~systemverilog
   /* 
   2022-12-31 v1: 王哲完成模块
   2022-01-01 v2.1: 王哲修复xx问题
   2022-01-01 v2.2: yy修复xx问题
   2022-01-02 v2.m: zz合并v2.1,v2.2
   */
   ~~~

7. 对于每一个systemVerilog模块，都需要对应的testbench证明其功能符合预期。最初始的testbench可以非常简单，但要为后续添加新的测试输入向量做好准备。testbench文件与模块同目录，使用模块名_tb命名。

8. 不允许使用限定FPGA的任何ip核或者相关语法宏，对于大容积的存储器，需要使用包装后的高层模块（为了便于后续流片）。

9. 发现问题需要调整别人代码时，及时在微信群中告知。如果本人可以解决相关问题，则在本地解决之后及时提交，否之，出现问题的同学提供出问题的tb，push到git上之后，由负责相关问题模块代码的同学完成调试更新。

10. git的使用上，每一个人实现某功能时，需要先从development分支上单独新建一个分支，分支命名格式为，姓名首字母_分支开发内容 在完成相关开发之后，在微信群中告知，等待合入dev分支。合并之后删除相关分支。在dev完成度到达一定阶段时（跑通性能测试/功能测试/uboot/linux等），会创建stable分支（命名为stable\_日期），并合入main。

    ~~~
    main
    dev
    
    aaa_add_computations_docs
    bbb_add_load_store_docs
    ccc_imple_alu_ver_1
    ...
    ~~~

11. 代码风格上，要求对于可变信号，统一使用*全小写的下划线命名法*，对于define的预处理定义，使用*下划线开头的全大写下划线命名法*，对于参数parameter和locaparameter，使用*非下划线开头的全大写下划线命名法*

    ~~~systemverilog
    `define _CONST_DEF 1
    logic data_i;
    parameter int LEN = 1;
    localparam STATE_START = 0;
    ~~~

12. 对于模块命名，统一使用全小写的下划线命名法，模块所在的文件名，与模块同名，后缀加上ver标注版本。

13. 对于握手信号的命名（一收一发），接收测使用 xxx_ready 表示发送的消息已经收到，发送测使用 xxx_valid 表示某消息已经就绪。

14. 对于接口信号命名，接口（尽量避免使用）使用\_if作为结尾，输入使用\_i作为结尾，输出使用\_o作为结尾，inout口使用\_io作为结尾。

15. 对于接口上重复的多个相同接口，要求使用数组，不允许使用类似\_1,\_2这种格式声明多个标量端口。

16. 对于类型的定义，使用\_t作为结尾

17. 对于数组的定义，使用类似这种结构完成：

    ```systemverilog
    logic[arr_size - 1 : 0][data_size - 1 : 0] arr;
    // 一个长度为arr_size的数组，其元素长度为data_size
    
    logic[arr_size_1 - 1 : 0][arr_size_2 - 1 : 0][data_size - 1 : 0] md_arr;
    // 一个第一维长度为arr_size_1，第二维为arr_size_2的二维数组，其元素长度为data_size
    
    typdef struct packed {
    	...    
    }demo_t;
    demo_t[arr_size - 1 : 0]demo_arr;
    // 一个长度为arr_size的数组，其元素长度为demo_t结构体的对象
    ```

## 核心架构

（2023.1.4暂定）

![image-20230104135358874](D:\Source\FPGA\new_cpu\pic\image-20230104135358874.png)





