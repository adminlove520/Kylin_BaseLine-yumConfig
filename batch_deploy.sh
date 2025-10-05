#!/bin/bash
# 麒麟系统V10 SP3 基线加固批量执行工具（优化版）
# 1. 移除免密登录配置（已由step_ssh_免密.sh完成）
# 2. 支持下载markdown和csv结果文件
# 3. 增加多线程支持
# 版本: 1.7
# 日期: 2025-10-05

# 配置参数
LOCAL_SCRIPT_PATH="./kylin_baseline.sh"       # 本地加固脚本路径
REMOTE_DIR="/home/baseline"                  # 远程目标路径
REMOTE_SCRIPT_NAME="kylin_baseline.sh"       # 远程脚本名称
SERVER_LIST="servers.txt"                    # 服务器列表文件
SSH_PORT=22                                  # SSH端口
# 修改：使用setup_ssh_免密.sh生成的密钥文件
KEY_FILE="$HOME/.ssh/id_rsa_ssh_setup"       # 使用SSH免密配置脚本生成的密钥文件
MASTER_NODE=""                               # 主节点(接收结果)
MASTER_RESULT_PATH="/home/baseline/result_all"  # 主节点结果存储路径
# 新增：实际结果文件路径
REMOTE_CSV_PATH="/tmp/baseline_result.csv"   # 远程CSV结果文件路径
REMOTE_MD_PATH="/tmp/*_baseline_*.md"        # 远程Markdown结果文件路径（使用通配符）
THREAD_COUNT=1                               # 默认线程数

# 确保环境变量正确处理特殊字符
export SHELL=/bin/bash

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m"  # 无颜色

# 统计变量
total_count=0
current_count=0
success_count=0
fail_count=0

# 禁用可能导致脚本中断的选项
set +euo pipefail

# 检查本地加固脚本是否存在
check_local_script() {
    if [ ! -f "$LOCAL_SCRIPT_PATH" ]; then
        echo -e "${RED}错误: 本地加固脚本 $LOCAL_SCRIPT_PATH 不存在!${NC}"
        exit 1
    fi
}

# 检查服务器列表和密码文件
check_server_files() {
    if [ ! -f "$SERVER_LIST" ]; then
        echo -e "${RED}错误: 服务器列表文件 $SERVER_LIST 不存在!${NC}"
        exit 1
    fi

    # 生成干净的临时服务器列表
    tr -d '[:cntrl:]' < "$SERVER_LIST" | grep -oE 'root@[0-9.]+|^[0-9.]+$' | dos2unix > "$SERVER_LIST.tmp" 2>/dev/null
    total_count=$(wc -l < "$SERVER_LIST.tmp")
    
    if [ $total_count -eq 0 ]; then
        echo -e "${RED}错误: $SERVER_LIST 中没有有效服务器记录!${NC}"
        rm -f "$SERVER_LIST.tmp"
        exit 1
    fi
    
    echo -e "${BLUE}检测到有效服务器数量: $total_count 台${NC}"
}

# 部署加固脚本到远程服务器
deploy_script() {
    local server=$1
    local user=$(echo "$server" | cut -d'@' -f1)
    local host=$(echo "$server" | cut -d'@' -f2)
    
    if [ "$user" = "$host" ]; then
        user="root"
    fi
    
    echo -e "${BLUE}部署加固脚本到 $user@$host ...${NC}"
    
    ssh -i "$KEY_FILE" -p "$SSH_PORT" "$user@$host" "mkdir -p $REMOTE_DIR && chmod 700 $REMOTE_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}创建远程目录 $REMOTE_DIR 失败${NC}"
        return 1
    fi
    
    scp -i "$KEY_FILE" -P "$SSH_PORT" "$LOCAL_SCRIPT_PATH" \
        "$user@$host:$REMOTE_DIR/$REMOTE_SCRIPT_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}加固脚本已部署到 $user@$host:$REMOTE_DIR${NC}"
        return 0
    else
        echo -e "${RED}部署加固脚本到 $user@$host 失败${NC}"
        return 1
    fi
}

# 执行远程加固脚本
execute_remote_script() {
    local server=$1
    local user=$(echo "$server" | cut -d'@' -f1)
    local host=$(echo "$server" | cut -d'@' -f2)
    
    if [ "$user" = "$host" ]; then
        user="root"
    fi
    
    echo -e "${BLUE}在 $user@$host 上执行加固脚本...${NC}"
    
    # 执行脚本（增加超时和保活，改进命令格式避免特殊字符问题）
    ssh -o ConnectTimeout=30 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 \
        -i "$KEY_FILE" -p "$SSH_PORT" "$user@$host" <<EOF
cd $REMOTE_DIR && chmod +x $REMOTE_SCRIPT_NAME && 
{ echo 12; sleep 2; echo; sleep 1; echo 0; sleep 1; } | ./$REMOTE_SCRIPT_NAME
EOF
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}$user@$host 加固脚本执行完成${NC}"
        return 0
    else
        echo -e "${RED}$user@$host 加固脚本执行失败${NC}"
        return 1
    fi
}

# 下载结果文件（支持markdown和csv格式）
download_result_files() {
    local server=$1
    local user=$(echo "$server" | cut -d'@' -f1)
    local host=$(echo "$server" | cut -d'@' -f2)
    
    if [ "$user" = "$host" ]; then
        user="root"
    fi
    
    echo -e "${BLUE}从 $user@$host 下载结果文件...${NC}"
    
    # 创建本地结果目录
    mkdir -p ./results
    
    # 下载CSV结果文件
    scp -i "$KEY_FILE" -P "$SSH_PORT" "$user@$host:$REMOTE_CSV_PATH" \
        "./results/${host}_baseline_result.csv" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}CSV结果文件已下载: ./results/${host}_baseline_result.csv${NC}"
    else
        echo -e "${YELLOW}警告: 无法下载 $user@$host 的CSV结果文件${NC}"
    fi
    
    # 下载Markdown结果文件（使用通配符匹配）
    scp -i "$KEY_FILE" -P "$SSH_PORT" "$user@$host:$REMOTE_MD_PATH" \
        "./results/" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Markdown结果文件已下载到: ./results/${NC}"
    else
        echo -e "${YELLOW}警告: 无法下载 $user@$host 的Markdown结果文件${NC}"
    fi
}

# 准备主节点接收结果
prepare_master_node() {
    if [ -z "$MASTER_NODE" ]; then
        echo -e "${YELLOW}未指定主节点，跳过结果回传步骤${NC}"
        return 0
    fi
    
    local user=$(echo "$MASTER_NODE" | cut -d'@' -f1)
    local host=$(echo "$MASTER_NODE" | cut -d'@' -f2)
    
    if [ "$user" = "$host" ]; then
        user="root"
    fi
    
    echo -e "\n${BLUE}准备主节点 $user@$host 接收结果...${NC}"
    
    ssh -i "$KEY_FILE" -p "$SSH_PORT" "$user@$host" "mkdir -p $MASTER_RESULT_PATH && chmod 700 $MASTER_RESULT_PATH"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}主节点结果目录准备完成: $user@$host:$MASTER_RESULT_PATH${NC}"
        return 0
    else
        echo -e "${RED}无法在主节点创建结果目录${NC}"
        return 1
    fi
}

# 将本地结果上传到主节点
upload_results_to_master() {
    if [ -z "$MASTER_NODE" ]; then
        return 0
    fi
    
    local user=$(echo "$MASTER_NODE" | cut -d'@' -f1)
    local host=$(echo "$MASTER_NODE" | cut -d'@' -f2)
    
    if [ "$user" = "$host" ]; then
        user="root"
    fi
    
    echo -e "\n${BLUE}上传结果到主节点 $user@$host...${NC}"
    
    # 检查本地结果目录是否有文件（忽略空文件）
    if [ ! -d "./results" ] || [ -z "$(find ./results -type f -size +0)" ]; then
        echo -e "${YELLOW}本地结果目录为空或无有效文件，跳过上传${NC}"
        return 0
    fi
    
    scp -i "$KEY_FILE" -P "$SSH_PORT" ./results/* "$user@$host:$MASTER_RESULT_PATH/"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}结果已上传到主节点 $user@$host:$MASTER_RESULT_PATH${NC}"
        return 0
    else
        echo -e "${RED}结果上传到主节点失败${NC}"
        return 1
    fi
}

# 处理单台服务器（用于多线程）
process_single_server() {
    local server=$1
    local index=$2
    
    echo -e "\n${YELLOW}===== 线程$index 处理服务器: $server =====${NC}"
    
    # 步骤1：部署脚本
    deploy_script "$server"
    if [ $? -ne 0 ]; then
        echo -e "${RED}脚本部署失败，跳过该服务器${NC}"
        return 1
    fi
    
    # 步骤2：执行加固脚本
    execute_remote_script "$server"
    if [ $? -ne 0 ]; then
        echo -e "${RED}脚本执行失败${NC}"
        return 1
    fi
    
    # 步骤3：下载结果文件
    download_result_files "$server"
    
    echo -e "${YELLOW}===== 线程$index 服务器处理完成 =====${NC}\n"
    return 0
}

# 批量处理服务器（支持多线程）
process_servers() {
    echo -e "${BLUE}===== 开始批量处理服务器（共 $total_count 台，线程数: $THREAD_COUNT）=====${NC}"
    
    echo -e "${BLUE}调试：临时文件 $SERVER_LIST.tmp 行数: $total_count${NC}"
    echo -e "${BLUE}调试：临时文件前5行内容:${NC}"
    head -n 5 "$SERVER_LIST.tmp"
    
    # 如果线程数为1，使用原有顺序处理方式
    if [ $THREAD_COUNT -eq 1 ]; then
        # 行号索引遍历所有服务器
        i=1
        while [ $i -le $total_count ]; do
            server=$(sed -n "${i}p" "$SERVER_LIST.tmp")
            if [ -z "$server" ]; then
                echo -e "${YELLOW}调试：第 $i 行为空，跳过${NC}"
            else
                current_count=$((current_count + 1))
                echo -e "\n${YELLOW}===== 处理第 $current_count 台服务器: $server =====${NC}"
                
                # 步骤1：部署脚本
                deploy_script "$server"
                if [ $? -ne 0 ]; then
                    echo -e "${RED}脚本部署失败，跳过该服务器${NC}"
                    fail_count=$((fail_count + 1))
                else
                    # 步骤2：执行加固脚本
                    execute_remote_script "$server"
                    if [ $? -ne 0 ]; then
                        echo -e "${RED}脚本执行失败${NC}"
                        fail_count=$((fail_count + 1))
                    else
                        # 步骤3：下载结果文件
                        download_result_files "$server"
                        success_count=$((success_count + 1))
                    fi
                fi
                
                echo -e "${YELLOW}===== 第 $current_count 台服务器处理完成 =====${NC}\n"
            fi
            i=$((i + 1))
        done
    else
        # 多线程处理
        pids=""
        server_index=0
        processed_count=0
        
        # 分批处理服务器
        while [ $server_index -lt $total_count ]; do
            # 启动最多THREAD_COUNT个并发任务
            current_batch=0
            while [ $current_batch -lt $THREAD_COUNT ] && [ $server_index -lt $total_count ]; do
                server_index=$((server_index + 1))
                server=$(sed -n "${server_index}p" "$SERVER_LIST.tmp")
                if [ -z "$server" ]; then
                    echo -e "${YELLOW}调试：第 $server_index 行为空，跳过${NC}"
                    current_batch=$((current_batch - 1))
                else
                    # 在后台启动处理任务
                    process_single_server "$server" "$server_index" &
                    new_pid=$!
                    pids="$pids $new_pid"
                    current_count=$((current_count + 1))
                    processed_count=$((processed_count + 1))
                    current_batch=$((current_batch + 1))
                    echo -e "${BLUE}启动线程处理服务器: $server (PID: $new_pid)${NC}"
                fi
            done
            
            # 等待当前批次完成
            for pid in $pids; do
                wait $pid
                if [ $? -eq 0 ]; then
                    success_count=$((success_count + 1))
                else
                    fail_count=$((fail_count + 1))
                fi
            done
            
            # 清空PID字符串
            pids=""
        done
    fi
    
    rm -f "$SERVER_LIST.tmp"
}

# 显示帮助信息
show_help() {
    echo "麒麟系统V10 SP3 基线加固批量执行工具"
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help             显示帮助信息"
    echo "  -m, --master 节点      指定主节点（格式：用户名@IP地址），用于接收结果报告"
    echo "  -t, --threads 数量     指定并发线程数（默认: 1）"
    echo
    echo "示例:"
    echo "  $0 -m root@10.58.37.50 -t 5"
}

# 显示结果汇总
show_summary() {
    echo -e "\n${BLUE}===== 批量处理结果汇总 ====="${NC}
    echo -e "总服务器数: $total_count"
    echo -e "实际处理数: $current_count"
    echo -e "${GREEN}成功处理: $success_count${NC}"
    echo -e "${RED}处理失败: $fail_count${NC}"
    
    if [ $current_count -lt $total_count ]; then
        echo -e "${YELLOW}警告: 部分服务器未处理，请检查临时文件或手动处理${NC}"
    fi
    
    echo -e "\n${GREEN}本地结果存储路径: $(pwd)/results${NC}"
    if [ ! -z "$MASTER_NODE" ]; then
        echo -e "${GREEN}主节点结果路径: $MASTER_NODE:$MASTER_RESULT_PATH${NC}"
    fi
}

# 主程序
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -m|--master)
                MASTER_NODE="$2"
                shift 2
                ;;
            -t|--threads)
                THREAD_COUNT="$2"
                # 验证线程数
                if ! [[ "$THREAD_COUNT" =~ ^[0-9]+$ ]] || [ "$THREAD_COUNT" -lt 1 ]; then
                    echo -e "${RED}错误: 线程数必须是大于0的整数${NC}"
                    exit 1
                fi
                shift 2
                ;;
            *)
                echo -e "${RED}未知选项: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    check_local_script
    check_server_files
    
    if [ ! -z "$MASTER_NODE" ]; then
        prepare_master_node
    fi
    
    process_servers
    
    if [ ! -z "$MASTER_NODE" ]; then
        upload_results_to_master
    fi
    
    show_summary
}

# 启动主程序
main "$@"
