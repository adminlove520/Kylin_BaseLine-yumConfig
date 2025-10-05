#!/bin/bash
# SSH免密登录批量配置工具（终极修复版）
# 彻底解决只读取第一条服务器记录的问题
# 优化：支持密码包含特殊字符，增强文件格式验证，使用环境变量传递密码
# 版本: 1.6
# 日期: 2025-10-05

# 配置参数
SERVER_LIST="servers.txt"                   # 服务器列表文件
PASSWORD_FILE=".server_passwords.txt"       # 密码文件（格式：IP:密码）
KEY_FILE="$HOME/.ssh/id_rsa_ssh_setup"      # 专用SSH密钥文件
SSH_PORT=22                                 # SSH端口
TIMEOUT=10                                  # SSH连接超时时间（秒）
MAX_RETRIES=2                               # 失败重试次数

# 创建日志文件记录执行过程
LOG_FILE="ssh_setup_$(date +%Y%m%d_%H%M%S).log"
echo "开始执行SSH免密配置 - $(date)" > "$LOG_FILE"

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m"  # 无颜色

# 统计变量
success_count=0
fail_count=0
total_count=0
current_count=0  # 当前处理序号

# 禁用所有可能导致脚本中断的选项，增强脚本稳定性
set +euo pipefail

# 检查必要文件是否存在并验证格式
check_files() {
    if [ ! -f "$SERVER_LIST" ]; then
        echo -e "${RED}错误: 服务器列表文件 $SERVER_LIST 不存在！${NC}"
        exit 1
    fi

    if [ ! -f "$PASSWORD_FILE" ]; then
        echo -e "${RED}错误: 密码文件 $PASSWORD_FILE 不存在！${NC}"
        exit 1
    fi

    # 验证密码文件格式
    if ! grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:' "$PASSWORD_FILE"; then
        echo -e "${RED}错误: 密码文件格式不正确，应为 'IP:密码' 格式！${NC}"
        exit 1
    fi

    # 生成干净的临时文件并统计行数（强制转换为纯文本）
    tr -d '[:cntrl:]' < "$SERVER_LIST" | grep -oE 'root@[0-9.]+|^[0-9.]+' | dos2unix > "$SERVER_LIST.tmp" 2>/dev/null
    total_count=$(wc -l < "$SERVER_LIST.tmp")
    
    if [ $total_count -eq 0 ]; then
        echo -e "${RED}错误: $SERVER_LIST 中没有有效服务器记录！${NC}"
        rm -f "$SERVER_LIST.tmp"
        exit 1
    fi
    echo -e "${BLUE}检测到有效服务器数量: $total_count 台${NC}"
    echo "[INFO] 检测到有效服务器数量: $total_count 台" >> "$LOG_FILE"
}

# 生成SSH密钥对
generate_ssh_key() {
    if [ ! -f "$KEY_FILE" ]; then
        echo -e "${BLUE}生成专用SSH密钥对...${NC}"
        ssh-keygen -t rsa -b 2048 -f "$KEY_FILE" -N "" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}生成SSH密钥对失败！${NC}"
            exit 1
        fi
        echo -e "${GREEN}SSH密钥对生成成功: $KEY_FILE${NC}"
    else
        echo -e "${BLUE}使用现有SSH密钥: $KEY_FILE${NC}"
    fi
}

# 获取密码（支持密码中包含冒号）
get_password() {
    local ip=$1
    # 使用cut -d: -f2-提取完整密码，支持密码中包含冒号
    local password=$(grep -E "^${ip}:" "$PASSWORD_FILE" | cut -d: -f2-)
    if [ -n "$password" ]; then
        echo "$password"
        return 0
    else
        return 1
    fi
}

# 配置单台服务器免密登录（带重试机制）
setup_ssh() {
    local server=$1
    local user
    local host
    local retries=0
    local success=false

    # 支持两种格式：root@ip 或直接 ip
    if [[ "$server" == *"@"* ]]; then
        user=$(echo "$server" | cut -d'@' -f1)
        host=$(echo "$server" | cut -d'@' -f2)
    else
        user="root"
        host="$server"
    fi

    current_count=$((current_count + 1))
    echo -e "\n${YELLOW}===== 处理第 $current_count 台服务器: $user@$host =====${NC}"
    echo "[INFO] 开始处理: $user@$host" >> "$LOG_FILE"

    # 检查是否已免密登录
    if ssh -o StrictHostKeyChecking=no -o BatchMode=yes \
           -o ConnectTimeout=$TIMEOUT -o ServerAliveCountMax=2 \
           -i "$KEY_FILE" -p "$SSH_PORT" "$user@$host" "echo" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 已配置免密登录，跳过${NC}"
        echo "[INFO] $host 已配置免密登录，跳过" >> "$LOG_FILE"
        success_count=$((success_count + 1))
        return 0
    fi

    # 获取密码
    local password=$(get_password "$host")
    if [ -z "$password" ]; then
        echo -e "${RED}✗ 未找到 $host 的密码记录${NC}"
        echo "[ERROR] 未找到 $host 的密码记录" >> "$LOG_FILE"
        fail_count=$((fail_count + 1))
        return 1
    fi

    # 带重试机制的免密配置
    while [ $retries -le $MAX_RETRIES ]; do
        if [ $retries -gt 0 ]; then
            echo -e "${YELLOW}重试中 ($retries/$MAX_RETRIES)...${NC}"
        fi

        # 配置免密登录（使用环境变量传递密码，支持特殊字符）
        echo -e "${BLUE}配置免密登录...${NC}"
        set +H
        # 使用SSHPASS环境变量传递密码，避免特殊字符解析问题
        SSHPASS="$password" sshpass -e ssh-copy-id -o StrictHostKeyChecking=no \
            -o ConnectTimeout=$TIMEOUT -o ServerAliveCountMax=2 \
            -i "$KEY_FILE.pub" -p "$SSH_PORT" "$user@$host" > /dev/null 2>&1
        set -H

        # 验证
        if ssh -o StrictHostKeyChecking=no -o BatchMode=yes \
               -o ConnectTimeout=$TIMEOUT -i "$KEY_FILE" -p "$SSH_PORT" "$user@$host" "echo" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ 免密登录配置成功${NC}"
            echo "[SUCCESS] $host 免密登录配置成功" >> "$LOG_FILE"
            success_count=$((success_count + 1))
            success=true
            break
        else
            echo -e "${RED}✗ 配置尝试失败${NC}"
            retries=$((retries + 1))
        fi
    done

    if [ "$success" = false ]; then
        echo -e "${RED}✗ 免密登录配置失败（已达最大重试次数）${NC}"
        echo "[FAIL] $host 免密登录配置失败（已达最大重试次数）" >> "$LOG_FILE"
        fail_count=$((fail_count + 1))
    fi
}

# 批量处理所有服务器（核心：用行号索引遍历，完全规避数组问题）
process_all() {
    echo -e "${BLUE}===== 开始批量配置免密登录（共 $total_count 台服务器）=====${NC}"
    
    # 调试临时文件
    echo -e "${BLUE}调试：临时文件 $SERVER_LIST.tmp 行数: $total_count${NC}"
    echo -e "${BLUE}调试：临时文件前5行内容:${NC}"
    head -n 5 "$SERVER_LIST.tmp"
    
    # 关键：通过行号索引逐行读取（从1到total_count）
    for ((i=1; i<=total_count; i++)); do
        # 读取第i行内容
        server=$(sed -n "${i}p" "$SERVER_LIST.tmp")
        # 跳过空行
        if [ -z "$server" ]; then
            echo -e "${YELLOW}调试：第 $i 行为空，跳过${NC}"
            continue
        fi
        echo -e "${BLUE}调试：读取到第 $i 台服务器 -> $server${NC}"
        setup_ssh "$server"
    done
    
    rm -f "$SERVER_LIST.tmp"
}

# 显示结果
show_summary() {
    echo -e "\n${BLUE}===== 配置结果汇总 =====${NC}"
    echo -e "总服务器数: $total_count"
    echo -e "实际处理数: $current_count"
    echo -e "${GREEN}成功配置: $success_count${NC}"
    echo -e "${RED}配置失败: $fail_count${NC}"
    
    # 计算成功率
    if [ $current_count -gt 0 ]; then
        local success_rate=$((success_count * 100 / current_count))
        echo -e "${YELLOW}配置成功率: $success_rate%${NC}"
    fi
    
    if [ $current_count -lt $total_count ]; then
        echo -e "${YELLOW}警告: 实际处理数量少于总服务器数${NC}"
        echo -e "${YELLOW}建议手动检查未处理的服务器${NC}"
    fi
    
    # 记录汇总结果到日志
    echo "[SUMMARY] 总服务器数: $total_count, 处理数: $current_count, 成功: $success_count, 失败: $fail_count" >> "$LOG_FILE"
    echo "执行完成 - $(date)" >> "$LOG_FILE"
    echo -e "${BLUE}详细日志已保存至: $LOG_FILE${NC}"
}

# 主程序
main() {
    check_files
    generate_ssh_key
    process_all
    show_summary
}

# 启动主程序
main
