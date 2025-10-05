#!/bin/bash
# 服务器列表生成工具（多格式版）
# 同时支持CSV和XLSX文件，自动识别格式
# 生成适用于加固脚本的servers.txt和密码文件
# 版本: 2.0
# 日期: 2025-10-04

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m"  # 无颜色

# 输出文件
SERVER_LIST="servers.txt"
PASSWORD_FILE=".server_passwords.txt"  # 隐藏文件存储密码

# 检查文件类型并返回处理方式
detect_file_type() {
    local file=$1
    local ext="${file##*.}"
    
    case "$ext" in
        csv|CSV)
            echo "csv"
            ;;
        xlsx|XLSX)
            echo "xlsx"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 检查基础依赖（python3）
check_base_dependencies() {
    echo -e "${BLUE}检查基础依赖...${NC}"
    
    # 检查python3
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}错误: 未安装python3，请先安装python3${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}基础依赖检查通过${NC}"
}

# 检查XLSX所需依赖（pandas和openpyxl）
check_xlsx_dependencies() {
    echo -e "${BLUE}检查XLSX处理依赖...${NC}"
    
    # 检查pandas
    if ! python3 -c "import pandas" &> /dev/null; then
        echo -e "${YELLOW}未安装pandas，尝试安装...${NC}"
        local install_success=0
        
        # 尝试系统包管理器安装
        if command -v yum &> /dev/null; then
            yum install -y python3-pandas python3-openpyxl &> /dev/null
            if python3 -c "import pandas" &> /dev/null; then
                install_success=1
            fi
        elif command -v apt &> /dev/null; then
            apt install -y python3-pandas python3-openpyxl &> /dev/null
            if python3 -c "import pandas" &> /dev/null; then
                install_success=1
            fi
        fi
        
        # 尝试pip安装
        if [ $install_success -eq 0 ]; then
            echo -e "${YELLOW}尝试用pip安装...${NC}"
            
            # 检查pip3
            if ! command -v pip3 &> /dev/null; then
                echo -e "${YELLOW}安装pip3...${NC}"
                if command -v yum &> /dev/null; then
                    yum install -y python3-pip &> /dev/null
                elif command -v apt &> /dev/null; then
                    apt install -y python3-pip &> /dev/null
                fi
            fi
            
            # 用pip安装
            if command -v pip3 &> /dev/null; then
                pip3 install pandas openpyxl --user &> /dev/null
                if python3 -c "import pandas" &> /dev/null; then
                    install_success=1
                fi
            fi
        fi
        
        # 安装失败
        if [ $install_success -eq 0 ]; then
            echo -e "${RED}无法安装pandas，请手动安装后重试:${NC}"
            echo -e "${RED}  pip3 install pandas openpyxl --user${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}XLSX依赖检查通过${NC}"
}

# 从CSV文件生成服务器列表和密码文件（无额外依赖）
generate_from_csv() {
    local csv_file=$1
    
    echo -e "${BLUE}使用CSV模式处理: $csv_file${NC}"
    
    # 使用python内置csv模块处理
    python3 - <<END
import csv
import os

try:
    with open("$csv_file", 'r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        required_columns = ['IP', '账号', '密码']
        missing_columns = [col for col in required_columns if col not in reader.fieldnames]
        
        if missing_columns:
            print(f"${RED}CSV文件缺少必要的列: {', '.join(missing_columns)}${NC}")
            exit(1)
        
        # 生成服务器列表和密码文件
        with open("$SERVER_LIST", "w") as server_f, \
             open("$PASSWORD_FILE", "w") as pass_f:
             
            server_f.write("# 自动生成的服务器列表\n")
            server_f.write("# 格式: 用户名@IP地址\n")
            
            pass_f.write("# 自动生成的服务器密码文件\n")
            pass_f.write("# 格式: IP地址:密码\n")
            
            # 处理每一行数据
            for row_num, row in enumerate(reader, 2):
                ip = row['IP'].strip() if row['IP'] else ""
                user = row['账号'].strip() if row['账号'] else ""
                password = row['密码'].strip() if row['密码'] else ""
                
                if not ip or not user:
                    print(f"${YELLOW}警告: 第{row_num}行IP或账号为空，已跳过${NC}")
                    continue
                
                server_f.write(f"{user}@{ip}\n")
                pass_f.write(f"{ip}:{password}\n")

    print(f"${GREEN}成功生成服务器列表: {os.path.abspath('$SERVER_LIST')}${NC}")
    print(f"${GREEN}成功生成密码文件: {os.path.abspath('$PASSWORD_FILE')}${NC}")
    print(f"${YELLOW}注意: 密码文件权限已设置为仅当前用户可见${NC}")

except Exception as e:
    print(f"${RED}处理CSV文件失败: {str(e)}${NC}")
    exit(1)
END
    
    chmod 600 $PASSWORD_FILE
}

# 从XLSX文件生成服务器列表和密码文件（需要pandas）
generate_from_xlsx() {
    local xlsx_file=$1
    
    echo -e "${BLUE}使用XLSX模式处理: $xlsx_file${NC}"
    
    # 使用pandas处理XLSX
    python3 - <<END
import pandas as pd
import os

try:
    df = pd.read_excel("$xlsx_file")
except Exception as e:
    print(f"${RED}读取XLSX文件失败: {str(e)}${NC}")
    exit(1)

# 检查必要的列
required_columns = ['IP', '账号', '密码']
missing_columns = [col for col in required_columns if col not in df.columns]

if missing_columns:
    print(f"${RED}XLSX文件缺少必要的列: {', '.join(missing_columns)}${NC}")
    exit(1)

# 清理数据
df = df.dropna(subset=['IP', '账号'])

# 生成服务器列表
with open("$SERVER_LIST", "w") as f:
    f.write("# 自动生成的服务器列表\n")
    f.write("# 格式: 用户名@IP地址\n")
    for index, row in df.iterrows():
        ip = str(row['IP']).strip()
        user = str(row['账号']).strip()
        if user and ip:
            f.write(f"{user}@{ip}\n")

# 生成密码文件
with open("$PASSWORD_FILE", "w") as f:
    f.write("# 自动生成的服务器密码文件\n")
    f.write("# 格式: IP地址:密码\n")
    for index, row in df.iterrows():
        ip = str(row['IP']).strip()
        password = str(row['密码']).strip() if pd.notna(row['密码']) else ""
        if ip:
            f.write(f"{ip}:{password}\n")

print(f"${GREEN}成功生成服务器列表: {os.path.abspath('$SERVER_LIST')}${NC}")
print(f"${GREEN}成功生成密码文件: {os.path.abspath('$PASSWORD_FILE')}${NC}")
print(f"${YELLOW}注意: 密码文件权限已设置为仅当前用户可见${NC}")
END
    
    chmod 600 $PASSWORD_FILE
}

# 获取指定IP的密码
get_password() {
    local ip=$1
    
    if [ ! -f "$PASSWORD_FILE" ]; then
        echo -e "${YELLOW}密码文件 $PASSWORD_FILE 不存在${NC}"
        return 1
    fi
    
    local password=$(grep "^$ip:" $PASSWORD_FILE | cut -d: -f2)
    echo "$password"
    return 0
}

# 显示帮助信息
show_help() {
    echo "服务器列表生成工具（多格式版）"
    echo "支持CSV和XLSX文件，自动识别格式"
    echo "用法: $0 [选项] <数据文件路径>"
    echo "选项:"
    echo "  -h, --help           显示帮助信息"
    echo "  -g, --get-password   获取指定IP的密码，用法: $0 -g <IP地址>"
    echo
    echo "文件格式要求:"
    echo "  1. CSV文件: 第一行为表头，必须包含: IP,账号,密码（英文逗号分隔）"
    echo "  2. XLSX文件: 必须包含名为'IP','账号','密码'的列"
    echo "示例:"
    echo "  $0 servers.csv        # 处理CSV文件"
    echo "  $0 servers.xlsx       # 处理XLSX文件"
    echo "  $0 -g 192.168.1.100   # 获取指定IP的密码"
}

# 主程序
main() {
    # 检查参数
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    # 处理选项
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_help
        exit 0
    elif [ "$1" = "-g" ] || [ "$1" = "--get-password" ]; then
        if [ $# -ne 2 ]; then
            echo -e "${RED}错误: 请指定IP地址${NC}"
            echo "用法: $0 -g <IP地址>"
            exit 1
        fi
        get_password "$2"
        exit 0
    else
        local data_file="$1"
        
        # 检查文件是否存在
        if [ ! -f "$data_file" ]; then
            echo -e "${RED}错误: 文件 $data_file 不存在${NC}"
            exit 1
        fi
        
        # 检测文件类型
        local file_type=$(detect_file_type "$data_file")
        if [ "$file_type" = "unknown" ]; then
            echo -e "${RED}错误: 不支持的文件格式，请使用CSV或XLSX文件${NC}"
            exit 1
        fi
        
        # 检查基础依赖
        check_base_dependencies
        
        # 根据文件类型处理
        if [ "$file_type" = "csv" ]; then
            generate_from_csv "$data_file"
        else
            # 处理XLSX前检查额外依赖
            check_xlsx_dependencies
            generate_from_xlsx "$data_file"
        fi
    fi
}

# 启动主程序
main "$@"
