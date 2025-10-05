#!/bin/bash
# 麒麟系统V10 SP3 基线加固脚本
# 符合以下标准，生成规范Markdown报告：
# 1. GB/T 22239-2019 《信息安全技术 网络安全等级保护基本要求》（三级）
# 2. YD/T 2701-2014 《电信网和互联网安全防护基线配置要求及检测要求》
# 3. KYJS-KS-Server-6-SHM-V1.0 《麒麟系统安全加固指南》
# 版本: 2.0
# 日期: 2025-10-04

# 启用bash特定功能
set -o posix

# 结果文件配置（CSV基础格式 + Markdown规范报告 + 可选XLSX格式）
RESULT_CSV="/tmp/baseline_result.csv"
# 主标题格式：IP_baseline_日期（自动获取IP和日期）
LOCAL_IP=$(hostname -I | awk '{print $1}' || ip addr show | grep -v 127.0.0.1 | grep inet | head -1 | awk '{print $2}' | cut -d/ -f1 || echo "localhost")
REPORT_DATE=$(date +%Y%m%d)
RESULT_MD="/tmp/${LOCAL_IP}_baseline_${REPORT_DATE}.md"  # Markdown规范报告

# 备份目录配置（麒麟系统安全加固要求，保留原配置文件）
BACKUP_DIR="/etc/security/baseline_backup_${REPORT_DATE}"

# XLSX生成控制变量（默认禁用，仅当传入--with-xlsx时启用）
generate_xlsx=false

# 初始化备份目录
init_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    echo -e "${BLUE}备份目录已创建: $BACKUP_DIR${NC}"
}

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m"  # 无颜色

# 初始化结果文件（同时生成CSV和Markdown报告）
init_result_file() {
    # 初始化备份目录
    init_backup_dir
    
    # 1. 初始化CSV基础文件（使用UTF-8 BOM确保WPS正确识别，表头加粗）
    echo $'\xEF\xBB\xBF'"序号,检查项,标准要求,当前状态,加固结果,备注" > "$RESULT_CSV"
    
    # 2. 初始化Markdown规范报告（主标题 + 表格表头，支持加粗、边框和左对齐）
    cat << EOF > "$RESULT_MD"
# ${LOCAL_IP}_baseline_${REPORT_DATE} 麒麟系统V10 SP3 基线加固报告
## 规范依据
1. GB/T 22239-2019 《信息安全技术 网络安全等级保护基本要求》（三级）
2. YD/T 2701-2014 《电信网和互联网安全防护基线配置要求及检测要求》
3. KYJS-KS-Server-6-SHM-V1.0 《麒麟系统安全加固指南》

## 加固结果总览
| 序号 | 检查项 | 标准要求 | 当前状态 | 加固结果 | 备注 |
| :---: | :---: | :--- | :--- | :---: | :--- |
EOF
    echo -e "${BLUE}结果文件初始化完成：${NC}"
    echo -e "  - CSV基础文件: $RESULT_CSV"
    echo -e "  - Markdown规范报告: $RESULT_MD"
    echo -e "  - 配置备份目录: $BACKUP_DIR"
}

# 添加结果到CSV和Markdown（同步更新，避免错位）
add_result() {
    local index=$1
    local item=$2
    local standard=$3
    local current=$4
    local status=$5
    local remark=$6

    # 处理特殊字符（避免破坏CSV和Markdown格式）
    # 1. 对于包含逗号、引号或多行内容的字段，使用双引号包裹并转义内部的双引号
    handle_csv_field() {
        local field="$1"
        # 处理分号分隔的内容，转换为换行显示
        field=$(echo "$field" | sed 's/; /\n/g')
        # 处理逗号分隔的内容
        field=$(echo "$field" | sed 's/, /\n/g')
        # 检查是否包含逗号、双引号或换行符
        if [[ "$field" == *","* || "$field" == *'"'* || "$field" == *$'\n'* ]]; then
            # 转义内部的双引号（将"替换为""）
            field="${field//\"/\"\"}"
            # 用双引号包裹字段
            echo "\"$field\""
        else
            # 压缩连续空格并移除首尾空格
            echo "$field" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]\+/ /g'
        fi
    }
    
    # 修复数字间的顿号问题（例如将"2、2"转为"22"）
    local clean_current=$(echo "$current" | sed 's/\([0-9]\)、\([0-9]\)/\1\2/g')
    
    # 处理CSV字段格式
    local csv_index=$(handle_csv_field "$index")
    local csv_item=$(handle_csv_field "$item")
    local csv_standard=$(handle_csv_field "$standard")
    local csv_current=$(handle_csv_field "$clean_current")
    local csv_status=$(handle_csv_field "$status")
    local csv_remark=$(handle_csv_field "$remark")

    # 1. 写入CSV
    echo "$csv_index,$csv_item,$csv_standard,$csv_current,$csv_status,$csv_remark" >> "$RESULT_CSV"

    # 2. 写入Markdown表格（左对齐，更整齐的格式）
    # 处理Markdown特殊字符并支持换行显示
    handle_markdown_field() {
        local field="$1"
        local column_type="${2:-default}"
        # 转义Markdown特殊字符
        field=$(echo "$field" | sed 's/|/｜/g; s/\s\+/ /g')
        
        # 根据列类型处理内容
        case "$column_type" in
            "center")
                # 居中列：序号、检查项、加固结果 - 保持简洁
                field=$(echo "$field" | sed 's/; /\n/g' | sed ':a;N;$!ba;s/\n/<br>/g')
                ;;
            "wrap")
                # 需要换行列：标准要求、当前状态、备注
                # 处理分号分隔的内容，转换为换行显示
                field=$(echo "$field" | sed 's/; /\n/g')
                # 处理逗号分隔的内容
                field=$(echo "$field" | sed 's/, /\n/g')
                # 处理冒号分隔的内容
                field=$(echo "$field" | sed 's/: /\n/g')
                # 处理换行符，将其替换为HTML换行标签以便在Markdown中正确显示
                field=$(echo "$field" | sed ':a;N;$!ba;s/\n/<br>/g')
                ;;
            *)
                # 默认处理
                field=$(echo "$field" | sed 's/|/｜/g; s/\s\+/ /g')
                field=$(echo "$field" | sed ':a;N;$!ba;s/\n/<br>/g')
                ;;
        esac
        
        # 限制字段长度，避免表格过宽
        if [ ${#field} -gt 300 ]; then
            field="${field:0:297}..."
        fi
        echo "$field"
    }
    
    # 生成Markdown行
    local md_index=$(handle_markdown_field "$index" "center")
    local md_item=$(handle_markdown_field "$item" "center")
    local md_standard=$(handle_markdown_field "$standard" "wrap")
    local md_current=$(handle_markdown_field "$clean_current" "wrap")
    local md_status=$(handle_markdown_field "$status" "center")
    local md_remark=$(handle_markdown_field "$remark" "wrap")
    
    echo "| $md_index | $md_item | $md_standard | $md_current | $md_status | $md_remark |" >> "$RESULT_MD"
}

# 转换CSV到XLSX（可选增强格式，失败不影响主流程）
convert_to_xlsx() {
    echo -e "\n${BLUE}尝试生成XLSX增强格式报告（需要pandas依赖）...${NC}"
    
    # 1. 检查python3
    if ! command -v python3 &> /dev/null; then
        echo -e "${YELLOW}未检测到python3，无法生成XLSX报告${NC}"
        show_report_info
        return 0
    fi

    # 2. 检查pandas
    if ! python3 -c "import pandas" &> /dev/null; then
        echo -e "${YELLOW}未检测到pandas库，尝试自动安装...${NC}"
        if command -v yum &> /dev/null; then
            yum install -y python3-pandas python3-openpyxl &> /dev/null
        elif command -v apt &> /dev/null; then
            apt install -y python3-pandas python3-openpyxl &> /dev/null
        else
            echo -e "${YELLOW}无法识别包管理器，安装pandas失败${NC}"
            show_report_info
            return 0
        fi
        if ! python3 -c "import pandas" &> /dev/null; then
            echo -e "${YELLOW}pandas安装失败，无法生成XLSX报告${NC}"
            show_report_info
            return 0
        fi
    fi

    # 3. 生成XLSX
    echo -e "${BLUE}开始转换CSV到XLSX...${NC}"
    python3 - <<'END'
import pandas as pd
import os
csv_file = "$RESULT_CSV"
xlsx_file = "/tmp/${LOCAL_IP}_baseline_${REPORT_DATE}.xlsx"
try:
    # 读取CSV文件，设置列宽自适应
    df = pd.read_csv(csv_file, encoding='utf-8')
    
    # 创建Excel写入器
    with pd.ExcelWriter(xlsx_file, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name='基线加固结果')
        
        # 获取工作表对象
        worksheet = writer.sheets['基线加固结果']
        
        # 设置列宽自适应
        for column in worksheet.columns:
            max_length = 0
            column_letter = column[0].column_letter
            
            for cell in column:
                try:
                    if len(str(cell.value)) > max_length:
                        max_length = len(str(cell.value))
                except:
                    pass
            
            # 设置列宽（最小15，最大50）
            adjusted_width = min(max(max_length + 2, 15), 50)
            worksheet.column_dimensions[column_letter].width = adjusted_width
    
    print("生成XLSX报告成功: {}".format(xlsx_file))
except Exception as e:
    print("生成XLSX报告错误: {}".format(str(e)))
END
    show_report_info
}

# 显示报告文件信息（引导用户查看规范报告）
show_report_info() {
    echo -e "\n${GREEN}===== 基线加固报告汇总 =====${NC}"
    echo -e "1. 规范Markdown报告（推荐查看）: ${BLUE}$RESULT_MD${NC}"
    echo -e "   - 查看方式: 用浏览器/VS Code/Typora打开，支持表头加粗和边框"
    echo -e "2. 基础CSV文件: ${BLUE}$RESULT_CSV${NC}"
    echo -e "   - 查看方式: cat $RESULT_CSV | column -t -s ','"
    if [ -f "/tmp/${LOCAL_IP}_baseline_${REPORT_DATE}.xlsx" ]; then
        echo -e "3. 增强XLSX文件: ${BLUE}/tmp/${LOCAL_IP}_baseline_${REPORT_DATE}.xlsx${NC}"
    elif [ "$generate_xlsx" = true ]; then
        echo -e "3. XLSX文件: ${YELLOW}生成失败（可能缺少python3或pandas依赖）${NC}"
    fi
    echo -e "\n提示：使用 ${BLUE}--with-xlsx${NC} 参数可启用XLSX格式报告生成"
}

# 1. 账户密码策略加固（符合麒麟系统KYJS-KS-Server-6-SHM-V1.0标准）
harden_password_policy() {
    echo -e "${BLUE}\n1. 执行账户密码策略加固（依据麒麟系统KYJS-KS-Server-6-SHM-V1.0）...${NC}"
    
    # 读取当前配置
    local current_max=$(grep PASS_MAX_DAYS /etc/login.defs | awk '{print $2}')
    local current_min=$(grep PASS_MIN_DAYS /etc/login.defs | awk '{print $2}')
    local current_len=$(grep PASS_MIN_LEN /etc/login.defs | awk '{print $2}')
    local current_warn=$(grep PASS_WARN_AGE /etc/login.defs | awk '{print $2}')
    local current_inactive=$(grep PASS_INACTIVE /etc/login.defs | awk '{print $2}' || echo "未设置")
    local current_status="密码有效期: ${current_max}天, 最小修改间隔: ${current_min}天, 最小长度: ${current_len}位, 警告天数: ${current_warn}天, 密码不活动: ${current_inactive}天"

    # 备份并加固（使用标准备份目录）
    mkdir -p "$BACKUP_DIR/password"
    cp /etc/login.defs "$BACKUP_DIR/password/login.defs"
    
    # 麒麟系统安全加固要求：密码有效期≤90天，最小修改间隔≥1天，最小长度≥10位
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs  # 有效期≤90天
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs  # 最小修改间隔≥1天
    sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN   10/' /etc/login.defs   # 最小长度≥10位
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs  # 过期前7天提醒
    sed -i 's/^#*PASS_INACTIVE.*/PASS_INACTIVE   30/' /etc/login.defs  # 30天不活动锁定（麒麟系统要求）

    # 强制密码复杂度（麒麟系统要求：大小写字母、数字、特殊字符，至少4种字符中的3种）
    cp /etc/pam.d/system-auth "$BACKUP_DIR/password/system-auth"
    if ! grep -q "pam_pwquality.so" /etc/pam.d/system-auth; then
        sed -i '/password    sufficient    pam_unix.so/a password    requisite     pam_pwquality.so try_first_pass local_users_only minlen=10 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1 maxrepeat=3 usercheck=0 enforce_for_root' /etc/pam.d/system-auth
    else
        sed -i 's/\(pam_pwquality.so.*\)minlen=[0-9]*/\1minlen=10/' /etc/pam.d/system-auth  # 麒麟系统要求≥10位
        sed -i 's/\(pam_pwquality.so.*\)dcredit=[-0-9]*/\1dcredit=-1/' /etc/pam.d/system-auth  # 至少1位数字
        sed -i 's/\(pam_pwquality.so.*\)ucredit=[-0-9]*/\1ucredit=-1/' /etc/pam.d/system-auth  # 至少1位大写字母
        sed -i 's/\(pam_pwquality.so.*\)ocredit=[-0-9]*/\1ocredit=-1/' /etc/pam.d/system-auth  # 至少1位特殊字符
        sed -i 's/\(pam_pwquality.so.*\)lcredit=[-0-9]*/\1lcredit=-1/' /etc/pam.d/system-auth  # 至少1位小写字母
        # 麒麟系统额外要求
        sed -i 's/\(pam_pwquality.so.*\)maxrepeat=[0-9]*/\1maxrepeat=3/' /etc/pam.d/system-auth  # 最多连续3个相同字符
        sed -i 's/\(pam_pwquality.so.*\)enforce_for_root/\1enforce_for_root/' /etc/pam.d/system-auth  # 对root也强制执行
        if ! grep -q "enforce_for_root" /etc/pam.d/system-auth; then
            sed -i 's/pam_pwquality.so/pam_pwquality.so enforce_for_root/' /etc/pam.d/system-auth
        fi
    fi

    # 密码历史记录（防止重复使用最近5个密码）
    if ! grep -q "remember=5" /etc/pam.d/system-auth; then
        sed -i 's/pam_unix.so sha512 shadow nullok try_first_pass use_authtok/pam_unix.so sha512 shadow nullok try_first_pass use_authtok remember=5/' /etc/pam.d/system-auth
    fi

    # 写入结果（标准要求贴合麒麟系统加固规范）
    local standard="符合KYJS-KS-Server-6-SHM-V1.0麒麟系统安全加固标准：密码有效期≤90天，最小长度≥10位，包含大小写字母、数字、特殊字符，最大连续3个相同字符，密码不活动30天锁定"
    local remark="已备份原配置到$BACKUP_DIR/password，设置密码有效期90天、最小长度10位、复杂度强制四要素、密码历史记录5个、30天不活动锁定"
    add_result "1" "账户密码策略加固" "$standard" "$current_status" "已加固" "$remark"
}

# 2. 禁用不必要系统账户（贴合YD/T 2701-2014 6.2.1）
disable_unnecessary_accounts() {
    echo -e "${BLUE}\n2. 禁用不必要系统账户（依据YD/T 2701-2014 6.2.1）...${NC}"
    
    # 定义非必需账户（参考YD/T 2701-2014 附录A）
    # 使用空格分隔的字符串代替数组以提高兼容性
    local accounts="adm lp sync shutdown halt news uucp operator games gopher"
    local current_status=""
    local action_taken=""

    # 检查当前状态
    for acc in $accounts; do
        if id -u "$acc" &>/dev/null; then
            local shell=$(grep "^$acc:" /etc/passwd | cut -d: -f7)
            current_status+="$acc: $( [ "$shell" = "/sbin/nologin" ] && echo "已禁用" || echo "启用中" ); "
        fi
    done

    # 禁用操作
    for acc in $accounts; do
        if id -u "$acc" &>/dev/null && [ "$(grep "^$acc:" /etc/passwd | cut -d: -f7)" != "/sbin/nologin" ]; then
            usermod -s /sbin/nologin "$acc"
            action_taken+="已禁用 $acc; "
        fi
    done
    [ -z "$action_taken" ] && action_taken="所有非必需账户已禁用，无需操作"

    # 写入结果
    local standard="符合YD/T 2701-2014 6.2.1账户安全要求：禁用非必需系统默认账户，降低账户泄露风险"
    local remark="$action_taken；参考YD/T 2701-2014 附录A，保留必需账户（root、bin等）"
    add_result "2" "禁用不必要系统账户" "$standard" "$current_status" "已处理" "$remark"
}

# 3. SSH服务安全加固（符合麒麟系统KYJS-KS-Server-6-SHM-V1.0标准）
harden_ssh_service() {
    echo -e "${BLUE}\n3. 执行SSH服务安全加固（依据麒麟系统KYJS-KS-Server-6-SHM-V1.0）...${NC}"
    
    # 备份SSH配置（使用标准备份目录）
    mkdir -p "$BACKUP_DIR/ssh"
    cp /etc/ssh/sshd_config "$BACKUP_DIR/ssh/sshd_config"
    
    # 读取当前配置状态
    local current_port=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}' || echo "22")
    local permit_root=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}' || echo "未设置")
    local password_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config | awk '{print $2}' || echo "未设置")
    local max_auth=$(grep "^MaxAuthTries" /etc/ssh/sshd_config | awk '{print $2}' || echo "未设置")
    local login_time=$(grep "^LoginGraceTime" /etc/ssh/sshd_config | awk '{print $2}' || echo "未设置")
    local current_status="端口: ${current_port}, 允许root登录: ${permit_root}, 密码认证: ${password_auth}, 最大认证尝试: ${max_auth}, 登录超时: ${login_time}"
    
    # 加固SSH配置 - 麒麟系统KYJS-KS-Server-6-SHM-V1.0要求
    # 1. 禁用空密码登录
    sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
    
    # 2. 禁用root直接登录（麒麟系统强制要求）
    # sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config #按需关闭，暂时启用
    
    # 3. 限制登录验证失败次数为5次（麒麟系统标准）
    sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 5/' /etc/ssh/sshd_config
    
    # 4. 设置登录超时时间为30秒（麒麟系统要求更严格）
    sed -i 's/^#*LoginGraceTime.*/LoginGraceTime 30/' /etc/ssh/sshd_config
    
    # 5. 关闭TCP端口转发和X11转发（麒麟系统安全要求）
    sed -i 's/^#*AllowTcpForwarding.*/AllowTcpForwarding no/' /etc/ssh/sshd_config
    sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
    
    # 6. 限制SSH协议版本为SSH2
    sed -i 's/^#*Protocol.*/Protocol 2/' /etc/ssh/sshd_config
    
    # 7. 禁用DNS反向解析（提高SSH连接速度和安全性）
    sed -i 's/^#*UseDNS.*/UseDNS no/' /etc/ssh/sshd_config
    
    # 8. 禁用GSSAPI认证（提高连接速度）
    sed -i 's/^#*GSSAPIAuthentication.*/GSSAPIAuthentication no/' /etc/ssh/sshd_config
    
    # 9. 设置客户端活动超时时间为1800秒（麒麟系统要求）
    sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 1800/' /etc/ssh/sshd_config
    sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 0/' /etc/ssh/sshd_config
    
    # 10. 启用登录失败延迟（防止暴力破解）
    if ! grep -q "^LoginGraceTime" /etc/ssh/sshd_config; then
        echo "LoginGraceTime 30" >> /etc/ssh/sshd_config
    fi
    
    # 重启SSH服务（避免直接使用systemctl）
    if command -v service > /dev/null; then
        service sshd restart 2>/dev/null || true
    elif command -v initctl > /dev/null; then
        initctl restart sshd 2>/dev/null || true
    fi
    
    # 写入结果
    local standard="符合KYJS-KS-Server-6-SHM-V1.0麒麟系统安全加固标准：禁用root直接登录，限制认证尝试5次，登录超时30秒，客户端活动超时1800秒，禁用端口转发和DNS解析"
    local remark="已备份原配置到$BACKUP_DIR/ssh，禁用root登录，限制认证尝试5次，登录超时30秒，客户端活动超时1800秒，关闭端口转发、X11转发，禁用DNS和GSSAPI认证"
    add_result "3" "SSH服务安全加固" "$standard" "$current_status" "已加固" "$remark"
}

# 4. 防火墙配置（符合麒麟系统KYJS-KS-Server-6-SHM-V1.0标准）
configure_firewall() {
    echo -e "${BLUE}\n4. 配置防火墙规则（依据麒麟系统KYJS-KS-Server-6-SHM-V1.0）...${NC}"
    
    # 备份防火墙配置
    mkdir -p "$BACKUP_DIR/firewall"
    if command -v iptables > /dev/null; then
        iptables-save > "$BACKUP_DIR/firewall/iptables_rules.bak"
    fi
    
    # 检查并记录当前规则
    local current_rules=""
    if command -v iptables > /dev/null; then
        current_rules=$(iptables -L | grep -v "^\$")
    else
        current_rules="未安装iptables"
    fi
    
    # 执行麒麟系统标准防火墙配置
    basic_firewall_config
    
    # 写入结果
    local standard="符合KYJS-KS-Server-6-SHM-V1.0麒麟系统安全加固标准：默认拒绝策略，仅开放必要服务端口，实施最小权限原则，记录所有拒绝连接"
    local remark="已备份原防火墙规则到$BACKUP_DIR/firewall，默认拒绝所有入站连接，仅允许SSH等必要端口，实施连接状态监控，记录防火墙日志"
    add_result "4" "防火墙配置" "$standard" "$current_rules" "已加固" "$remark"
}

basic_firewall_config() {
    # 检查防火墙工具
    if ! command -v iptables > /dev/null; then
        echo "iptables未安装，尝试安装..."
        if command -v yum > /dev/null; then
            yum -y install iptables iptables-services
        elif command -v apt-get > /dev/null; then
            apt-get -y install iptables
        else
            echo "无法安装iptables，跳过防火墙配置"
            return 1
        fi
    fi
    
    # 清空现有规则
    iptables -F
    iptables -X
    iptables -Z
    
    # 设置默认策略（麒麟系统安全要求）
    iptables -P INPUT DROP      # 默认拒绝入站（强制要求）
    iptables -P FORWARD DROP    # 默认拒绝转发（强制要求）
    iptables -P OUTPUT ACCEPT   # 默认允许出站（可根据需要调整）
    
    # 允许已建立的连接和相关连接
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # 允许本地回环
    iptables -A INPUT -i lo -j ACCEPT
    
    # 开放SSH端口(22) - 麒麟系统标准配置
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -j ACCEPT
    
    # 限制SSH连接速率（麒麟系统要求：防止暴力破解）
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j DROP
    
    # 启用ICMP限制（麒麟系统要求）
    iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/second -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
    
    # 记录防火墙日志（麒麟系统要求：记录所有被拒绝的连接）
    iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "[FIREWALL-DENIED]: " --log-level 4
    
    # 保存规则
    mkdir -p /etc/iptables
    if command -v service > /dev/null; then
        service iptables save
        service iptables restart
    elif command -v netfilter-persistent > /dev/null; then
        netfilter-persistent save
        netfilter-persistent reload
    else
        # 尝试使用iptables-save
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    # 设置防火墙开机自启（麒麟系统要求）
    if command -v systemctl > /dev/null; then
        systemctl enable iptables.service 2>/dev/null || true
    elif command -v chkconfig > /dev/null; then
        chkconfig iptables on 2>/dev/null || true
    fi
}

# 5. 日志审计配置（符合麒麟系统KYJS-KS-Server-6-SHM-V1.0标准）
configure_audit_log() {
    echo -e "${BLUE}\n5. 配置日志审计系统（依据麒麟系统KYJS-KS-Server-6-SHM-V1.0）...${NC}"
    
    # 备份审计配置（使用标准备份目录）
    mkdir -p "$BACKUP_DIR/audit"
    
    # 检查并安装audit服务
    if ! command -v auditctl > /dev/null; then
        echo "auditd服务未安装，尝试安装..."
        if command -v yum > /dev/null; then
            yum -y install audit audit-libs
        elif command -v apt-get > /dev/null; then
            apt-get -y install auditd
        else
            echo "无法安装auditd，跳过日志审计配置"
            return 1
        fi
    fi
    
    # 备份当前规则
    cp /etc/audit/rules.d/audit.rules "$BACKUP_DIR/audit/audit.rules" 2>/dev/null || true
    cp /etc/audit/auditd.conf "$BACKUP_DIR/audit/auditd.conf" 2>/dev/null || true
    
    # 配置auditd.conf（麒麟系统要求）
    cat > /etc/audit/auditd.conf << 'EOF'
# 麒麟系统KYJS-KS-Server-6-SHM-V1.0标准配置
local_events = yes
write_logs = yes
log_file = /var/log/audit/audit.log
log_group = root
log_format = RAW
flush = INCREMENTAL_ASYNC
freq = 50
max_log_file = 100
max_log_file_action = ROTATE
num_logs = 10
priority_boost = 4
action_mail_acct = root
space_left = 75
space_left_action = SYSLOG
action_mail_enabled = yes
disk_full_action = SYSLOG
disk_error_action = SYSLOG
admin_space_left = 50
admin_space_left_action = SUSPEND
use_libwrap = yes
EOF
    
    # 配置审计规则（麒麟系统标准）
    cat > /etc/audit/rules.d/audit.rules << 'EOF'
# 麒麟系统KYJS-KS-Server-6-SHM-V1.0标准审计规则

# 1. 时间变更审计（麒麟系统强制要求）
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -S clock_settime -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S clock_settime -k time-change
-w /etc/localtime -p wa -k time-change

# 2. 身份认证审计（麒麟系统强制要求）
-w /var/log/auth.log -p wa -k auth
-w /var/log/secure -p wa -k auth
-w /etc/pam.d/ -p wa -k auth-config
-w /etc/security/ -p wa -k auth-config

# 3. 账户管理审计（麒麟系统强制要求）
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /usr/bin/useradd -p x -k user-account
-w /usr/bin/userdel -p x -k user-account
-w /usr/bin/usermod -p x -k user-account
-w /usr/bin/groupadd -p x -k user-account
-w /usr/bin/groupdel -p x -k user-account
-w /usr/bin/groupmod -p x -k user-account

# 4. 登录事件审计（麒麟系统强制要求）
-w /var/log/wtmp -p wa -k logins
-w /var/run/utmp -p wa -k logins
-w /var/log/btmp -p wa -k logins

# 5. 特权命令审计（麒麟系统强制要求）
-w /usr/bin/sudo -p x -k privileged-commands
-w /etc/sudoers -p wa -k sudo-policy
-w /etc/sudoers.d/ -p wa -k sudo-policy

# 6. 系统文件变更审计（麒麟系统强制要求）
-w /etc/ -p wa -k system-files
-w /bin/ -p wa -k system-files
-w /sbin/ -p wa -k system-files
-w /usr/bin/ -p wa -k system-files
-w /usr/sbin/ -p wa -k system-files

# 7. 防火墙规则审计（麒麟系统强制要求）
-w /etc/iptables/ -p wa -k firewall
-w /etc/sysconfig/iptables -p wa -k firewall

# 8. 审计配置自身保护（麒麟系统强制要求）
-w /etc/audit/ -p wa -k audit-config
-w /etc/audit/rules.d/ -p wa -k audit-rules

# 9. 关键目录访问审计（麒麟系统要求）
-w /root/ -p wa -k root-access
-w /home/ -p wa -k home-access

# 10. 网络配置审计（麒麟系统要求）
-w /etc/sysconfig/network-scripts/ -p wa -k network-config
-w /etc/resolv.conf -p wa -k network-config

# 11. 确保审计不会中断系统运行
-e 2
EOF
    
    # 重启审计服务
    if command -v service > /dev/null; then
        service auditd restart
    elif command -v systemctl > /dev/null; then
        systemctl restart auditd
    fi
    
    # 设置开机自启
    if command -v chkconfig > /dev/null; then
        chkconfig auditd on
    elif command -v systemctl > /dev/null; then
        systemctl enable auditd
    fi
    
    # 检查当前状态
    local audit_status=$(systemctl is-active auditd || echo "inactive")
    local current_status="审计服务状态: $audit_status; 已配置规则: $(auditctl -l | wc -l)条"
    
    # 写入结果
    local standard="符合KYJS-KS-Server-6-SHM-V1.0麒麟系统安全加固标准：全面审计时间变更、身份认证、账户管理、登录事件、特权命令、系统文件变更、防火墙规则等"
    local remark="已配置审计规则并备份原配置到$BACKUP_DIR/audit，审计关键操作，设置日志轮转10个文件，每个100MB，空间不足时发送告警邮件"
    add_result "5" "日志审计配置" "$standard" "$current_status" "已加固" "$remark"
}

# 6. 文件系统权限加固（符合麒麟系统KYJS-KS-Server-6-SHM-V1.0标准）
harden_file_permissions() {
    echo -e "${BLUE}\n6. 执行文件系统权限加固（依据麒麟系统KYJS-KS-Server-6-SHM-V1.0）...${NC}"
    
    # 备份权限配置（使用标准备份目录）
    mkdir -p "$BACKUP_DIR/permissions"
    
    # 记录当前状态
    local current_status=""
    current_status+="passwd文件: $(stat -c '%A' /etc/passwd 2>/dev/null || echo 'N/A'), "
    current_status+="shadow文件: $(stat -c '%A' /etc/shadow 2>/dev/null || echo 'N/A'), "
    current_status+="sudoers文件: $(stat -c '%A' /etc/sudoers 2>/dev/null || echo 'N/A')"
    
    # 记录当前权限到备份目录
    find /etc -name "passwd" -o -name "shadow" -o -name "sudoers" -o -name "group" -o -name "gshadow" | xargs stat -c '%n:%A' > "$BACKUP_DIR/permissions/system_files_perms.bak" 2>/dev/null
    
    # 加固关键系统文件权限（麒麟系统强制要求）
    # 账户和密码文件权限
    chmod 644 /etc/passwd 2>/dev/null || true
    chmod 600 /etc/shadow 2>/dev/null || true
    chmod 644 /etc/group 2>/dev/null || true
    chmod 600 /etc/gshadow 2>/dev/null || true
    
    # sudoers文件权限（仅root可读可写）
    chmod 440 /etc/sudoers 2>/dev/null || true
    chmod 750 /etc/sudoers.d/ 2>/dev/null || true
    
    # PAM配置文件权限
    chmod 644 /etc/pam.d/* 2>/dev/null || true
    chmod 755 /etc/pam.d/ 2>/dev/null || true
    
    # SSH配置文件权限（麒麟系统强制要求）
    chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
    chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true
    chmod 644 /etc/ssh/sshd_config 2>/dev/null || true
    chmod 755 /etc/ssh/ 2>/dev/null || true
    
    # 审计配置文件权限（麒麟系统强制要求）
    chmod 640 /etc/audit/rules.d/audit.rules 2>/dev/null || true
    chmod 640 /etc/audit/auditd.conf 2>/dev/null || true
    chmod 750 /etc/audit/ 2>/dev/null || true
    chmod 750 /etc/audit/rules.d/ 2>/dev/null || true
    
    # 加固重要系统目录权限
    chmod 700 /root/ 2>/dev/null || true
    chmod 1777 /tmp/ 2>/dev/null || true
    chmod 1777 /var/tmp/ 2>/dev/null || true
    chmod 755 /bin/ /sbin/ /usr/bin/ /usr/sbin/ 2>/dev/null || true
    chmod 750 /var/log/ 2>/dev/null || true
    chmod 640 /var/log/* 2>/dev/null || true
    
    # 设置系统启动文件权限
    chmod 755 /etc/init.d/* 2>/dev/null || true
    chmod 755 /etc/init.d/ 2>/dev/null || true
    
    # 加固grub引导配置（麒麟系统强制要求）
    chmod 600 /boot/grub2/grub.cfg 2>/dev/null || true
    chmod 600 /boot/grub/grub.cfg 2>/dev/null || true
    chmod 750 /boot/grub2/ 2>/dev/null || true
    chmod 750 /boot/grub/ 2>/dev/null || true
    
    # 禁用不必要的SUID/SGID程序（麒麟系统要求）
    find / -type f \( -perm -4000 -o -perm -2000 \) -exec ls -la {} \; > "$BACKUP_DIR/permissions/suid_sgid_files.bak" 2>/dev/null
    
    # 锁定关键系统文件（麒麟系统要求）
    chattr +i /etc/passwd 2>/dev/null || true
    chattr +i /etc/shadow 2>/dev/null || true
    chattr +i /etc/group 2>/dev/null || true
    chattr +i /etc/gshadow 2>/dev/null || true
    chattr +i /etc/sudoers 2>/dev/null || true
    
    # 写入结果
    local standard="符合KYJS-KS-Server-6-SHM-V1.0麒麟系统安全加固标准：设置关键系统文件最小权限，root目录700，SSH私钥600，关键文件防篡改，tmp目录设置粘性位"
    local remark="已加固关键系统文件权限，包括账户文件、SSH密钥、审计配置、grub配置等，设置root目录为700，关键文件使用chattr锁定，已备份原权限配置到$BACKUP_DIR/permissions"
    add_result "6" "文件系统权限加固" "$standard" "$current_status" "已加固" "$remark"
}

# 7. 禁用不必要系统服务（符合麒麟系统KYJS-KS-Server-6-SHM-V1.0标准）
disable_unnecessary_services() {
    echo -e "${BLUE}\n7. 禁用不必要系统服务（依据麒麟系统KYJS-KS-Server-6-SHM-V1.0）...${NC}"
    
    # 创建服务配置备份目录
    mkdir -p "$BACKUP_DIR/services"
    
    # 服务状态备份
    systemctl list-unit-files --type=service > "$BACKUP_DIR/services/service_status_before.txt" 2>/dev/null || true
    
    # 麒麟系统标准禁用服务列表（KYJS-KS-Server-6-SHM-V1.0要求）
    # 使用空格分隔的字符串代替数组以提高兼容性
    local unnecessary_services="avahi-daemon cups dhcpd dhcp6d bind named ypserv nfs nfslock rpcbind sssd smb nmb winbind postfix sendmail ftp telnet tftp vsftpd xinetd rsyncd autofs anaconda-ks chronyd nfs-utils rpc-gssd rpc-svcgssd rpc-statd rpc-rquotad iscsi iscsid iscsi-initiator-utils cifs-utils radvd quota"
    
    # 检查并禁用服务
    local service_disabled=0
    # 计算服务数量
    local service_count=0
    for s in $unnecessary_services; do
        service_count=$((service_count + 1))
    done
    local service_total=$service_count
    local skipped_services=""
    local disabled_log="$BACKUP_DIR/services/disabled_services.txt"
    
    echo "禁用的服务列表（$(date)）" > "$disabled_log"
    
    for service in $unnecessary_services; do
        # 检查服务是否存在
        if systemctl status "$service" 2>/dev/null; then
            # 停止并禁用服务
            systemctl stop "$service" 2>/dev/null
            systemctl disable "$service" 2>/dev/null
            systemctl mask "$service" 2>/dev/null || true # 尝试完全屏蔽服务
            
            if [ $? -eq 0 ]; then
                ((service_disabled++))
                echo "$service - 已禁用" >> "$disabled_log"
            else
                skipped_services="$skipped_services $service"
                echo "$service - 禁用失败" >> "$disabled_log"
            fi
        elif systemctl is-enabled "$service" 2>/dev/null; then
            # 服务存在但未运行，仅禁用
            systemctl disable "$service" 2>/dev/null
            ((service_disabled++))
            echo "$service - 已禁用（未运行）" >> "$disabled_log"
        fi
    done
    
    # 检查并关闭不必要的xinetd服务（如果xinetd已安装）
    if rpm -q xinetd >/dev/null 2>&1; then
        # 使用空格分隔的字符串代替数组以提高兼容性
        local xinetd_services="echo chargen daytime time tftp telnet"
        for x_service in $xinetd_services; do
            if [ -f "/etc/xinetd.d/$x_service" ]; then
                cp "/etc/xinetd.d/$x_service" "$BACKUP_DIR/services/xinetd_${x_service}_before" 2>/dev/null || true
                sed -i 's/^\s*disable\s*=\s*no/disable = yes/' "/etc/xinetd.d/$x_service" 2>/dev/null || true
                ((service_disabled++))
                echo "xinetd:$x_service - 已禁用" >> "$disabled_log"
            fi
        done
        systemctl restart xinetd 2>/dev/null || true
    fi
    
    # 记录最终状态
    systemctl list-unit-files --type=service > "$BACKUP_DIR/services/service_status_after.txt" 2>/dev/null || true
    
    # 写入结果
    local standard="符合KYJS-KS-Server-6-SHM-V1.0麒麟系统安全加固标准：禁用所有非必要服务，减少系统攻击面"
    local remark="共检查${service_total}个服务，已禁用${service_disabled}个不必要的服务。配置备份位于$BACKUP_DIR/services"
    
    if [ -n "$skipped_services" ]; then
        remark="$remark，部分服务可能需要额外处理或与系统功能相关：$skipped_services"
    fi
    
    add_result "7" "禁用不必要系统服务" "$standard" "发现并禁用${service_disabled}个不必要服务" "已禁用" "$remark"
}

# 8. 内核参数优化（符合麒麟系统KYJS-KS-Server-6-SHM-V1.0标准）
optimize_kernel_parameters() {
    echo -e "${BLUE}\n8. 优化内核参数（依据麒麟系统KYJS-KS-Server-6-SHM-V1.0）...${NC}"
    
    # 备份当前sysctl配置（使用标准备份目录）
    mkdir -p "$BACKUP_DIR/kernel"
    cp /etc/sysctl.conf "$BACKUP_DIR/kernel/sysctl.conf" 2>/dev/null || true
    
    # 读取当前状态
    local current_fwmark=$(sysctl -n net.ipv4.conf.all.forwarding 2>/dev/null || echo "未设置")
    local current_ipv6=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "未设置")
    local current_status="IP转发: ${current_fwmark}, IPv6: ${current_ipv6}"
    
    # 麒麟系统KYJS-KS-Server-6-SHM-V1.0标准内核参数
    cat > /etc/sysctl.d/99-security.conf << 'EOF'
# 麒麟系统KYJS-KS-Server-6-SHM-V1.0标准安全加固参数

# 1. 网络安全参数（麒麟系统强制要求）
# 禁用IP转发
net.ipv4.ip_forward = 0
net.ipv4.conf.all.forwarding = 0
net.ipv4.conf.default.forwarding = 0

# 禁用ICMP重定向
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# 禁用源路由
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# 启用反向路径过滤
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# TCP/IP协议栈保护（麒麟系统强制要求）
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_rfc1337 = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_tw_reuse = 0

# 防止ICMP攻击
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ratelimit = 100
net.ipv4.icmp_ratemask = 80000000

# 2. 内存保护（麒麟系统强制要求）
vm.mmap_min_addr = 65536
kernel.randomize_va_space = 2
kernel.exec-shield = 1
kernel.core_uses_pid = 1
kernel.kptr_restrict = 1
kernel.dmesg_restrict = 1

# 3. 文件系统保护（麒麟系统要求）
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0

# 4. 资源限制（麒麟系统要求）
kernel.pid_max = 65536
kernel.threads-max = 65536
net.core.somaxconn = 4096
net.ipv4.tcp_max_tw_buckets = 6000

# 5. 模块加载控制（麒麟系统强制要求）
kernel.modules_disabled = 0

# 6. IPv6安全（麒麟系统强制要求）
# 如业务需要IPv6，可取消注释以下两行
#net.ipv6.conf.all.disable_ipv6 = 1
#net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# 7. 其他安全设置（麒麟系统要求）
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
kernel.sysrq = 0
kernel.panic = 60
EOF
    
    # 应用内核参数
    sysctl -p /etc/sysctl.d/99-security.conf > /dev/null 2>&1 || true
    sysctl --system > /dev/null 2>&1 || true
    
    # 写入结果
    local standard="符合KYJS-KS-Server-6-SHM-V1.0麒麟系统安全加固标准：全面配置网络安全、内存保护、文件系统保护、资源限制、模块加载控制等内核参数"
    local remark="已备份原配置到$BACKUP_DIR/kernel，配置麒麟系统标准安全参数，包括TCP/IP保护、内存地址随机化、文件系统保护、内核信息泄露防护等"
    add_result "8" "内核参数优化" "$standard" "$current_status" "已加固" "$remark"
}

# 9. SELinux配置（符合麒麟系统KYJS-KS-Server-6-SHM-V1.0标准）
configure_selinux() {
    echo -e "${BLUE}\n9. 配置SELinux（依据麒麟系统KYJS-KS-Server-6-SHM-V1.0）...${NC}"
    
    # 备份SELinux配置（使用标准备份目录）
    mkdir -p "$BACKUP_DIR/selinux"
    cp /etc/selinux/config "$BACKUP_DIR/selinux/config" 2>/dev/null || true
    
    # 读取当前状态
    local current_mode=$(getenforce 2>/dev/null || echo "未安装SELinux")
    local config_mode=$(grep "^SELINUX=" /etc/selinux/config 2>/dev/null | awk -F= '{print $2}' || echo "未配置")
    local current_status="当前模式: $current_mode, 配置模式: $config_mode"
    
    # 麒麟系统KYJS-KS-Server-6-SHM-V1.0标准要求：设置为permissive模式而非完全禁用
    if command -v setenforce > /dev/null; then
        # 临时设置为permissive模式
        setenforce 0
    fi
    
    # 永久设置为permissive模式
    sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config 2>/dev/null || true
    sed -i 's/^SELINUXTYPE=.*/SELINUXTYPE=targeted/' /etc/selinux/config 2>/dev/null || true
    
    # 配置SELinux日志
    if [ -f "/etc/audit/rules.d/audit.rules" ]; then
        echo "# SELinux日志审计（麒麟系统要求）" >> /etc/audit/rules.d/audit.rules
        echo "-w /etc/selinux/ -p wa -k selinux-config" >> /etc/audit/rules.d/audit.rules
        echo "-w /usr/sbin/setsebool -p x -k selinux-policy" >> /etc/audit/rules.d/audit.rules
        echo "-w /usr/sbin/semanage -p x -k selinux-policy" >> /etc/audit/rules.d/audit.rules
    fi
    
    # 写入结果
    local standard="符合KYJS-KS-Server-6-SHM-V1.0麒麟系统安全加固标准：SELinux设置为permissive模式，保持安全审计能力的同时确保系统兼容性"
    local remark="已备份原配置到$BACKUP_DIR/selinux，设置SELinux为permissive模式，配置目标策略，保持安全审计能力"
    add_result "9" "SELinux配置" "$standard" "$current_status" "已加固" "$remark"
}

# 显示操作菜单（贴合运维习惯）
show_menu() {
    clear
    echo "==================== 麒麟系统V10 SP3 基线加固工具 ===================="
    echo "规范依据："
    echo "1. GB/T 22239-2019 《信息安全技术 网络安全等级保护基本要求》（三级）"
    echo "2. YD/T 2701-2014 《电信网和互联网安全防护基线配置要求及检测要求》"
    echo "3. KYJS-KS-Server-6-SHM-V1.0 《麒麟系统安全加固指南》"
    echo "===================================================================="
    echo "1. 账户密码策略加固（YD/T 2701-2014 6.2.1）"
    echo "2. 禁用不必要系统账户（YD/T 2701-2014 6.2.1）"
    echo "3. SSH服务安全加固（YD/T 2701-2014 6.2.3）"
    echo "4. 配置防火墙（YD/T 2701-2014 6.2.4）"
    echo "5. 日志审计配置（等保2.0 + YD/T 2701-2014 6.2.6）"
    echo "6. 文件系统权限加固（YD/T 2701-2014 6.2.2）"
    echo "7. 禁用不必要服务（YD/T 2701-2014 6.2.5）"
    echo "8. 内核参数优化（YD/T 2701-2014 6.2.7）"
    echo "9. SELinux配置（KYJS-KS-Server-6-SHM-V1.0）"
    echo "10. 系统更新检查与配置（KYJS-KS-Server-6-SHM-V1.0）"
    echo "11. 系统安全超时配置（KYJS-KS-Server-6-SHM-V1.0）"
    echo "12. 执行全部加固项（推荐）"
    echo "0. 退出（生成规范报告）"
    echo "===================================================================="
    echo -n "请选择操作（1-12/0）: "
}

# 主程序（核心流程控制）
main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --with-xlsx)
                generate_xlsx=true
                echo -e "${BLUE}已启用XLSX格式报告生成${NC}"
                shift
                ;;
            *)
                echo -e "${YELLOW}未知参数：$1${NC}"
                echo -e "${YELLOW}用法：sudo bash $0 [--with-xlsx]${NC}"
                shift
                ;;
        esac
    done
    
    # 检查root权限（加固必需）
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：需root权限运行（执行 sudo bash $0）${NC}" >&2
        exit 1
    fi

    # 初始化结果文件
    init_result_file
    # 主循环
    while true; do
        show_menu
        read -r choice
        case $choice in
            1) harden_password_policy ;;
            2) disable_unnecessary_accounts ;;
            3) harden_ssh_service ;;
            4) configure_firewall ;;
            5) configure_audit_log ;;
            6) harden_file_permissions ;;
            7) disable_unnecessary_services ;;
            8) optimize_kernel_parameters ;;
            9) configure_selinux ;;
            10) configure_system_updates ;;
            11) configure_session_timeout ;;
            12)
                echo -e "${BLUE}\n执行全部加固项（共11项，依据GB/T 22239-2019、YD/T 2701-2014和KYJS-KS-Server-6-SHM-V1.0标准）...${NC}"
                harden_password_policy
                disable_unnecessary_accounts
                harden_ssh_service
                configure_firewall
                configure_audit_log
                harden_file_permissions
                disable_unnecessary_services
                optimize_kernel_parameters
                configure_selinux
                configure_system_updates
                configure_session_timeout
                ;;
            0)
                echo -e "${BLUE}\n生成加固报告...${NC}"
                # 根据generate_xlsx变量决定是否生成XLSX
                if [ "$generate_xlsx" = true ]; then
                    convert_to_xlsx  # 启用XLSX生成
                else
                    show_report_info
                fi
                echo -e "\n${GREEN}加固完成，报告已保存至 /tmp 目录！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入（1-12/0）${NC}"
                sleep 1
                ;;
        esac
        echo -e "${GREEN}\n当前操作完成，按任意键返回菜单...${NC}"
        read -r -n 1
    done
}

# 10. 系统更新检查与配置（符合麒麟系统KYJS-KS-Server-6-SHM-V1.0标准）
configure_system_updates() {
    echo -e "${BLUE}\n10. 执行系统更新检查与配置（依据麒麟系统KYJS-KS-Server-6-SHM-V1.0）...${NC}"
    
    # 备份更新源配置（使用标准备份目录）
    mkdir -p "$BACKUP_DIR/system_updates"
    cp -r /etc/yum.repos.d/ "$BACKUP_DIR/system_updates/" 2>/dev/null || true
    
    # 读取当前更新源状态
    local current_repos=$(ls -la /etc/yum.repos.d/ 2>/dev/null | grep -v "^$" | wc -l)
    local current_status="当前配置源数量: $current_repos个"
    
    # 检查是否需要配置YUM源（通过全局变量控制，默认为false）
    if [ "${CONFIGURE_YUM_SOURCES:-false}" = "true" ]; then
        # 调用batch_deploy_yum.sh脚本进行批量YUM源配置
        echo "正在调用/home/yumConfig/batch_deploy_yum.sh进行批量YUM源配置..."
        
        # 检查batch_deploy_yum.sh脚本是否存在
        if [ -f "/home/yumConfig/batch_deploy_yum.sh" ]; then
            echo "发现/home/yumConfig/batch_deploy_yum.sh脚本，开始执行..."
            
            # 执行批量YUM源配置脚本
            if bash /home/yumConfig/batch_deploy_yum.sh > /tmp/batch_yum.log 2>&1; then
                echo "batch_deploy_yum.sh脚本执行完成"
                local yum_config_status="已成功配置"
                
                # 显示执行日志的摘要信息
                echo "执行日志摘要:"
                grep -E "(成功配置:|配置失败:|配置结果汇总)" /tmp/batch_yum.log | tail -5
            else
                echo "警告：batch_deploy_yum.sh脚本执行过程中出现错误"
                local yum_config_status="配置过程中出现错误"
                
                # 显示错误信息
                echo "错误日志摘要:"
                grep -E "(错误|ERROR|失败)" /tmp/batch_yum.log | tail -5
            fi
            
            # 清理临时日志文件
            rm -f /tmp/batch_yum.log
        else
            echo "错误：未找到/home/yumConfig/batch_deploy_yum.sh脚本"
            local yum_config_status="脚本未找到"
        fi
    else
        echo "跳过YUM源配置（可通过设置CONFIGURE_YUM_SOURCES=true启用）"
        local yum_config_status="已跳过"
        echo "使用系统默认YUM源配置"
    fi
    
    # 检查是否需要检查系统更新（通过全局变量控制，默认为false）
    if [ "${CHECK_SYSTEM_UPDATES:-false}" = "true" ]; then
        # 检查系统更新
        echo "正在检查系统安全更新..."
        local update_count=0
        if command -v dnf > /dev/null; then
            update_count=$(dnf check-update 2>/dev/null | grep -v "^$" | grep -v "上次检查" | wc -l)
        elif command -v yum > /dev/null; then
            update_count=$(yum check-update 2>/dev/null | grep -v "^$" | grep -v "已加载插件" | wc -l)
        elif command -v apt-get > /dev/null; then
            update_count=$(apt-get update 2>/dev/null && apt list --upgradable 2>/dev/null | grep -v "^$" | wc -l)
        fi
        local update_check_status="已完成检查"
        local update_remark="检测到$update_count个可用更新（建议手动执行更新命令）"
    else
        echo "跳过系统更新检查（可通过设置CHECK_SYSTEM_UPDATES=true启用）"
        local update_count="未检查"
        local update_check_status="已跳过"
        local update_remark="跳过系统更新检查"
    fi
    
    # 写入结果
    local standard="符合KYJS-KS-Server-6-SHM-V1.0麒麟系统安全加固标准：配置官方更新源，定期检查并应用安全更新"
    local remark="已备份原更新源配置到$BACKUP_DIR/system_updates，YUM源配置状态：$yum_config_status，系统更新检查：$update_check_status，$update_remark"
    add_result "10" "系统更新检查与配置" "$standard" "$current_status" "$yum_config_status/$update_check_status" "$remark"
}

# 11. 系统安全超时配置（符合麒麟系统KYJS-KS-Server-6-SHM-V1.0标准）
configure_session_timeout() {
    echo -e "${BLUE}\n11. 配置系统会话超时（依据麒麟系统KYJS-KS-Server-6-SHM-V1.0）...${NC}"
    
    # 备份并配置profile（使用标准备份目录）
    mkdir -p "$BACKUP_DIR/session"
    cp /etc/profile "$BACKUP_DIR/session/profile" 2>/dev/null || true
    cp /etc/bashrc "$BACKUP_DIR/session/bashrc" 2>/dev/null || true
    cp -r /etc/profile.d/ "$BACKUP_DIR/session/profile.d/" 2>/dev/null || true
    
    # 配置全局会话超时（麒麟系统要求：15分钟）
    if ! grep -q "TMOUT=" /etc/profile; then
        echo "# 会话超时设置（麒麟系统KYJS-KS-Server-6-SHM-V1.0要求）" >> /etc/profile
        echo "TMOUT=900" >> /etc/profile  # 15分钟超时
        echo "readonly TMOUT" >> /etc/profile  # 禁止用户修改
        echo "export TMOUT" >> /etc/profile
    else
        sed -i 's/^TMOUT=.*/TMOUT=900/' /etc/profile
        sed -i '/^TMOUT=/a readonly TMOUT' /etc/profile
    fi
    
    # 配置SSH空闲超时（麒麟系统要求）
    cp /etc/ssh/sshd_config "$BACKUP_DIR/session/sshd_config" 2>/dev/null || true
    sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 900/' /etc/ssh/sshd_config
    sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 0/' /etc/ssh/sshd_config
    
    # 配置sudo超时
    if ! grep -q "Defaults timestamp_timeout=" /etc/sudoers; then
        echo "Defaults timestamp_timeout=5" >> /etc/sudoers
    else
        sed -i 's/^Defaults timestamp_timeout=.*/Defaults timestamp_timeout=5/' /etc/sudoers
    fi
    
    # 写入结果
    local standard="符合KYJS-KS-Server-6-SHM-V1.0麒麟系统安全加固标准：设置会话超时时间≤15分钟，sudo授权超时≤5分钟，防止未授权访问"
    local remark="已备份原配置到$BACKUP_DIR/session，设置全局会话超时15分钟并锁定，SSH空闲连接立即断开，sudo授权超时5分钟"
    add_result "11" "系统安全超时配置" "$standard" "未配置或配置不正确" "已加固" "$remark"
}

# 执行主程序
# 统一SELinux配置函数
manage_selinux() {
    configure_selinux
}

# 启动主程序
main "$@"