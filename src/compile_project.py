import os
try_chiplab_home = os.getenv('CHIPLAB_HOME')
target_path = '../dist'
if try_chiplab_home != '':
    target_path = try_chiplab_home + '/IP/myCPU/'
print("target_path: " + target_path)
sv_file_list = ['./inst/decoder.sv','./inst/decoder.svh']
os.system("cd inst/ && python3 gen_decoder.py")
for root, dirs, files in os.walk('../rtl'):
    for file in files:
        path = os.path.join(root, file)
        ext_name = os.path.splitext(path)[1]
        if (ext_name == '.sv' or ext_name == '.svh' or ext_name == '.v' or ext_name == '.vh') and 'logs/annotated/' not in path and 'decoder.sv' not in path and 'decoder.svh' not in path:
            sv_file_list.append(path)

os.system("rm -r " + target_path + " && mkdir " + target_path)
for file_path in sv_file_list:
    print(file_path)
    os.system("cp " + file_path + " " + target_path)
