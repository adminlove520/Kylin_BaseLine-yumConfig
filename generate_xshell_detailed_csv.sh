#!/bin/bash
# 生成带备注的Xshell导入CSV文件（修复版）
# 彻底解决字符串转义问题，避免f-string中的反斜杠错误
# 版本: 1.2
# 日期: 2025-10-04

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m"  # 无颜色

# 输入文件
SERVER_LIST="servers.txt"               # 服务器列表（用户名@IP）
PASSWORD_FILE=".server_passwords.txt"   # 密码文件（IP:密码）
ASSET_CSV="资产表.csv"                  # 资产表CSV（含所属系统和资源名称）

# 输出文件
XSHELL_CSV="xshell_import_with_notes.csv"

# 默认配置
DEFAULT_PROTOCOL="SSH"
DEFAULT_PORT="22"

# 检查输入文件
check_input_files() {
    echo -e "${BLUE}检查必要文件...${NC}"
    
    local missing=0
    
    if [ ! -f "$SERVER_LIST" ]; then
        echo -e "${RED}错误: 服务器列表文件 $SERVER_LIST 不存在${NC}"
        missing=1
    fi
    
    if [ ! -f "$PASSWORD_FILE" ]; then
        echo -e "${RED}错误: 密码文件 $PASSWORD_FILE 不存在${NC}"
        missing=1
    fi
    
    if [ ! -f "$ASSET_CSV" ]; then
        echo -e "${RED}错误: 资产表文件 $ASSET_CSV 不存在${NC}"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
    
    # 检查服务器列表是否有有效数据
    local valid_servers=$(grep -v '^#' "$SERVER_LIST" | grep -v '^$' | wc -l)
    if [ $valid_servers -eq 0 ]; then
        echo -e "${RED}错误: 服务器列表文件 $SERVER_LIST 中没有有效数据${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}所有必要文件检查通过${NC}"
}

# 生成Xshell导入CSV
generate_xshell_csv() {
    echo -e "${BLUE}正在生成带备注的Xshell导入CSV...${NC}"
    
    # 写入CSV表头（严格按照要求的字段顺序）
    cat << EOF > "$XSHELL_CSV"
Name,Host,Protocol,Port,User,Password,Description
EOF
    
    # 使用Python处理CSV数据，修复f-string反斜杠问题
    python3 - <<END
import csv
import os

# 从资产表CSV读取备注信息（所属系统+资源名称）
asset_notes = {}
try:
    with open("$ASSET_CSV", 'r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        # 检查资产表是否包含必要字段
        required_asset_cols = ['IP', '所属系统', '资源名称']
        missing_asset_cols = [col for col in required_asset_cols if col not in reader.fieldnames]
        if missing_asset_cols:
            print(f"${RED}错误: 资产表缺少必要字段: {', '.join(missing_asset_cols)}${NC}")
            exit(1)
            
        # 存储IP对应的备注信息
        for row in reader:
            ip = row['IP'].strip()
            system = row['所属系统'].strip() if '所属系统' in row else ''
            name = row['资源名称'].strip() if '资源名称' in row else ''
            if ip:
                asset_notes[ip] = f"{system}-{name}" if system or name else ""
except Exception as e:
    print(f"${RED}处理资产表失败: {str(e)}${NC}")
    exit(1)

# 读取密码文件
passwords = {}
try:
    with open("$PASSWORD_FILE", 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and ':' in line:
                ip, pwd = line.split(':', 1)
                passwords[ip.strip()] = pwd.strip()
except Exception as e:
    print(f"${RED}处理密码文件失败: {str(e)}${NC}")
    exit(1)

# 处理服务器列表并生成CSV内容
success_count = 0
skip_count = 0

with open("$SERVER_LIST", 'r') as f:
    for line_num, line in enumerate(f, 1):
        line = line.strip()
        # 跳过注释和空行
        if not line or line.startswith('#'):
            continue
            
        # 解析用户名和IP（格式：用户名@IP）
        if '@' not in line:
            print(f"${YELLOW}警告: 第{line_num}行格式错误（缺少@）: {line}，已跳过${NC}")
            skip_count += 1
            continue
            
        user, ip = line.split('@', 1)
        user = user.strip()
        ip = ip.strip()
        
        # 验证IP格式
        if not ip or (not ip.count('.') == 3 and not ':' in ip):
            print(f"${YELLOW}警告: 第{line_num}行IP格式无效: {ip}，已跳过${NC}")
            skip_count += 1
            continue
        
        # 获取密码
        password = passwords.get(ip, "")
        
        # 获取备注（所属系统+资源名称）
        description = asset_notes.get(ip, "无备注信息")
        
        # 会话名称（使用IP）
        session_name = ip
        
        # 处理CSV特殊字符（逗号、引号）- 彻底修复f-string反斜杠问题
        def escape_csv(s):
            if isinstance(s, str) and (',' in s or '"' in s or '\n' in s):
                # 先处理双引号，替换为两个双引号
                escaped = s.replace('"', '""')
                # 用双引号包裹处理后的字符串，避免在f-string中使用反斜杠
                return '"' + escaped + '"'
            return s
        
        # 构建CSV行
        csv_row = [
            escape_csv(session_name),
            escape_csv(ip),
            escape_csv("$DEFAULT_PROTOCOL"),
            escape_csv("$DEFAULT_PORT"),
            escape_csv(user),
            escape_csv(password),
            escape_csv(description)
        ]
        
        # 写入CSV
        with open("$XSHELL_CSV", 'a', encoding='utf-8') as csv_f:
            csv_f.write(','.join(csv_row) + '\n')
            
        success_count += 1

print(f"\n${GREEN}CSV文件生成完成: {os.path.abspath('$XSHELL_CSV')}${NC}")
print(f"${GREEN}成功导入 {success_count} 台服务器信息${NC}")
if skip_count > 0:
    print(f"${YELLOW}已跳过 {skip_count} 条无效记录${NC}")
print(f"\n${YELLOW}Xshell导入步骤:${NC}")
print(f"${YELLOW}1. 打开Xshell → 会话管理器 → 右键 → 导入 → 从CSV文件导入${NC}")
print(f"${YELLOW}2. 选择生成的 {os.path.basename('$XSHELL_CSV')} 文件${NC}")
print(f"${YELLOW}3. 确认字段匹配正确后点击确定${NC}")
END
}

# 显示帮助信息
show_help() {
    echo "生成带备注的Xshell导入CSV文件工具"
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help           显示帮助信息"
    echo "  -a, --asset 资产表   指定资产表CSV文件路径（默认: 资产表.csv）"
    echo "  -o, --output 文件    指定输出的CSV文件名（默认: xshell_import_with_notes.csv）"
    echo
    echo "示例:"
    echo "  $0                    # 使用默认资产表和输出文件名"
    echo "  $0 -a 我的资产表.csv   # 指定自定义资产表"
    echo "  $0 -o 服务器列表.csv   # 指定输出文件名"
}

# 主程序
main() {
    # 处理命令行参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--asset)
                ASSET_CSV="$2"
                shift 2
                ;;
            -o|--output)
                XSHELL_CSV="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}未知选项: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    check_input_files
    generate_xshell_csv
}

# 启动主程序
main "$@"
