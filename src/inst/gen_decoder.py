from functools import cmp_to_key
import json
import os
import types
import re

class decoder_parser:
    def __init__(self):
        self.const_list = []
        self.signal_package_list = set()
        self.signal_package_list.add('general')
        # format for signal_list's tuple: signal_parent, signal_length,signal_default_value,signal_invalid_value
        self.signal_list = {'inst25_0':('general',26,'inst_i[25:0]','inst_i[25:0]')}
        self.inst_list = {}

    def debug_print(self):
        print(self.const_list)
        print(self.signal_package_list)
        print(self.signal_list)
        print(self.inst_list)

    def parse_const(self,const_info ):
        for pair in const_info:
            self.const_list.append((pair,const_info[pair]))

    def parse_signal(self,signal_info ):
        for signal_name in signal_info:
            sub_dict = signal_info[signal_name]
            self.signal_package_list.add(sub_dict['stage'])
            self.signal_list[signal_name] = (sub_dict['stage'],sub_dict['length'],sub_dict['default_value'],sub_dict['invalid_value'])

    def parse_inst_list(self,inst_info ):
        for inst_name in inst_info:
            self.inst_list[inst_name] = inst_info[inst_name]
            text = inst_info[inst_name]['opcode']
            m = re.findall(r'-\d*-',text)
            for s in m:
                text = text.replace(s,int(s[1:-1]) * 'x')
            inst_info[inst_name]['opcode'] = text

    def parse_single_file(self,file_info ):
        if file_info.get('const') is not None:
            self.parse_const(file_info['const'])
        if file_info.get('signal') is not None:
            self.parse_signal(file_info['signal'])
        if file_info.get('inst') is not None:
            self.parse_inst_list(file_info['inst'])
        return

    def parse_all_file(self):
        json_path_list = []
        for root, dirs, files in os.walk('.'):
            for file in files:
                path = os.path.join(root, file)
                if os.path.splitext(path)[1] == '.json':
                    print(path)
                    json_path_list.append(path)
        for json_file_path in json_path_list:
            f = open(json_file_path)
            file_info = json.load(f)
            self.parse_single_file(file_info)
    
    def gen_sv_header(self):
        str_builder = "`ifndef _DECODE_HEADER\n`define _DECODE_HEADER\n\n"
        # const value define
        for const_value in self.const_list:
            str_builder += '`define '
            str_builder += const_value[0]
            str_builder += ' ('
            str_builder += const_value[1]
            str_builder += ')\n'
        str_builder += '\n'

        # struct define
        for leaf_struct in self.signal_list:
            str_builder += 'typedef logic['
            str_builder += str(self.signal_list[leaf_struct][1] - 1)
            str_builder += ' : 0] '
            str_builder += leaf_struct
            str_builder += '_t;\n'
        str_builder += '\n'
        for parent_struct in self.signal_package_list:
            str_builder += 'typedef struct packed {\n'
            for leaf_name in [signal_name for signal_name in self.signal_list if self.signal_list[signal_name][0] == parent_struct]:
                str_builder += '    ' + leaf_name + '_t ' + leaf_name + ';\n'
            str_builder += '}' + parent_struct + '_t;\n\n'

        # main_decode_struct define
        str_builder += 'typedef struct packed {\n'
        for parent_struct in self.signal_package_list:
            str_builder += '    ' + parent_struct + '_t ' + parent_struct + ';\n'
        str_builder += '}decode_info_t;\n\n'

        str_builder += "`endif\n"
        return str_builder

    def gen_blank(self,times ):
        return '    ' * times

    def dict_order_cmp(self,a,b):
        str_a = self.inst_list[a]['opcode']
        str_b = self.inst_list[b]['opcode']
        if len(str_a) != len(str_b):
            return (len(str_a) - len(str_b))
        str_a_std = str_a.replace('x','0')
        str_b_std = str_b.replace('x','0')
        return (int(str_a_std) - int(str_b_std))

    def gen_sv_module(self):
        str_builder = "`include \"common.svh\"\n`include \"decoder.svh\"\n\n"
        str_builder += "module decoder(\n    input logic[31:0] inst_i,\n    output decode_info_t decode_info_o,\n    output logic[31:0][7:0] inst_string_o\n);\n\n"
        
        # main combine logic
        depth = 1
        inst_list_dict_order = [inst_name for inst_name in self.inst_list]
        inst_list_dict_order.sort(key=cmp_to_key(self.dict_order_cmp))
        str_builder += self.gen_blank(depth) + "always_comb begin\n"
        depth += 1
        str_builder += self.gen_blank(depth) + "casex(inst_i)\n"
        depth += 1
        opcode_len = 0
        while len(inst_list_dict_order) != 0 and opcode_len != 32:
            if len(inst_list_dict_order) != 0 and len(self.inst_list[inst_list_dict_order[0]]['opcode']) > opcode_len:
                opcode_len += 1
                continue
            while len(inst_list_dict_order) != 0 and len(self.inst_list[inst_list_dict_order[0]]['opcode']) == opcode_len:
                inst = inst_list_dict_order[0]
                inst_list_dict_order.remove(inst)
                str_builder += self.gen_blank(depth) + "32'b" + self.inst_list[inst]['opcode'] + (32 - opcode_len) * 'x' + ': begin\n'
                depth += 1
                for signal in self.signal_list:
                    signal_value = ''
                    if self.inst_list[inst].get(signal) is not None:
                        signal_value = self.inst_list[inst].get(signal)
                    else:
                        signal_value = self.signal_list[signal][2]
                    if isinstance(signal_value,int):
                        signal_value = str(self.signal_list[signal][1]) + "\'d" + str(signal_value)
                        
                    str_builder += self.gen_blank(depth) + 'decode_info_o.' + self.signal_list[signal][0] + '.' + signal + ' = ' + signal_value + ';\n'
                str_builder += self.gen_blank(depth) + 'inst_string_o = {' + ' ,'.join(['8\'d' + str(ord(s)) for s in inst]) + '}; //' + inst + '\n'
                depth -= 1
                str_builder += self.gen_blank(depth) + "end\n"
        

        depth -= 1
        str_builder += self.gen_blank(depth) + "endcase\n"
        depth -= 1
        str_builder += self.gen_blank(depth) + "end\n\n"
        str_builder += "endmodule\n"
        return str_builder

if __name__ == '__main__':
    parser = decoder_parser()
    parser.parse_all_file()
    f = open('decoder.sv','w')
    f.write(parser.gen_sv_module())
    f.close()
    f = open('decoder.svh','w')
    f.write(parser.gen_sv_header())
    f.close()
