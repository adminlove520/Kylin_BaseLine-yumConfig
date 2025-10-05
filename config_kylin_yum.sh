#!/bin/bash

# 麒麟yum源配置脚本（整合SSH免密配置）
# 脚本目录: /home/yumConfig/
# 使用前请确保具有root权限

# 定义脚本目录
SCRIPT_DIR="/home/yumConfig"
SSH_SCRIPT="$SCRIPT_DIR/setup_ssh_免密.sh"

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以root用户权限运行，请使用sudo或切换到root用户后再试。"
    exit 1
fi

# 显示欢迎信息
echo "===== 麒麟操作系统yum源配置工具（整合版） ====="
echo "此工具将先配置SSH免密登录，再自动配置适合的yum源"
echo

# 检查并执行SSH免密配置脚本
echo "===== 开始执行SSH免密配置 ====="
if [ -f "$SSH_SCRIPT" ]; then
    echo "发现SSH免密配置脚本，开始执行..."
    chmod +x "$SSH_SCRIPT"
    "$SSH_SCRIPT"
    
    # 检查免密配置是否成功
    if [ $? -ne 0 ]; then
        echo "警告：SSH免密配置过程中出现错误"
        read -p "是否继续进行yum源配置？(y/n，默认y): " continue_choice
        if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "" ]; then
            echo "用户选择中止操作，退出脚本"
            exit 1
        fi
    fi
else
    echo "错误：未找到SSH免密配置脚本 $SSH_SCRIPT"
    read -p "是否继续进行yum源配置？(y/n，默认n): " continue_choice
    if [ "$continue_choice" != "y" ]; then
        echo "用户选择中止操作，退出脚本"
        exit 1
    fi
fi

echo
echo "===== 开始配置yum源 ====="
echo

# 获取并验证IP地址
while true; do
    read -p "请输入yum源IP地址: " IP
    
    # 简单验证IP格式
    if [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    else
        echo "IP地址格式无效，请重新输入"
    fi
done

# 根据IP自动判断网络环境
IP_PREFIX=$(echo "$IP" | cut -d. -f1-2)
case $IP_PREFIX in
    "10.58")
        NET_ENV="互联网"
        ;;
    "10.59")
        NET_ENV="政务外网"
        ;;
    *)
        NET_ENV="自定义网络"
        ;;
esac

echo "已识别网络环境: $NET_ENV (IP前缀: $IP_PREFIX)"
echo "已选择yum源IP: $IP"
echo

# 检测系统版本，确定spx值
echo "正在检测系统版本..."
if ! command -v nkvers &> /dev/null; then
    echo "警告：未找到nkvers命令，将尝试手动选择spx版本"
    echo "请选择spx版本："
    echo "1) sp1"
    echo "2) sp2"
    echo "3) sp3"
    read -p "请输入选项 (1/2/3): " spx_choice
    
    case $spx_choice in
        2)
            SPX="sp2"
            ;;
        3)
            SPX="sp3"
            ;;
        *)
            SPX="sp1"
            ;;
    esac
else
    # 执行nkvers命令并分析结果
    NKVERS_OUTPUT=$(nkvers)
    echo "系统版本信息："
    echo "$NKVERS_OUTPUT"
    echo
    
    # 检测sp版本
    if echo "$NKVERS_OUTPUT" | grep -qi "sp1"; then
        SPX="sp1"
    elif echo "$NKVERS_OUTPUT" | grep -qi "sp2"; then
        SPX="sp2"
    elif echo "$NKVERS_OUTPUT" | grep -qi "sp3"; then
        SPX="sp3"
    else
        echo "未检测到明确的sp版本，将使用默认值sp1"
        SPX="sp1"
    fi
fi

echo "已选择spx版本: $SPX"
echo

# 备份原有配置
echo "正在备份原有yum源配置..."
cd /etc/yum.repos.d || { echo "错误：无法进入/etc/yum.repos.d目录"; exit 1; }

# 创建备份目录（如果不存在）
mkdir -p bak

# 移动现有的麒麟相关repo文件到备份目录
mv -f kylin*.repo bak/ 2>/dev/null
mv -f x86_64.repo bak/ 2>/dev/null

echo "原有配置已备份到bak目录"
echo

# 创建新的yum源配置文件
echo "正在创建新的yum源配置文件..."
cat > local.repo << EOF
[ks10-adv-os]
name = Os
baseurl = http://$IP:8088/ky/$SPX/\$basearch/ks10-adv-os
gpgcheck = 0
enabled = 1

[ks10-adv-updates]
name = Updates
baseurl = http://$IP:8088/ky/$SPX/\$basearch/ks10-adv-updates
gpgcheck = 0
enabled = 1
EOF

# 检查配置文件是否创建成功
if [ -f "local.repo" ]; then
    echo "yum源配置文件创建成功"
    echo "配置内容如下："
    cat local.repo
else
    echo "错误：无法创建yum源配置文件"
    exit 1
fi

echo

# 清理并生成缓存
echo "正在清理yum缓存并生成新缓存..."
yum clean all
yum makecache

echo
echo "===== 所有配置完成 ====="
echo "网络环境: $NET_ENV"
echo "使用的yum源IP: $IP"
echo "使用的spx版本: $SPX"
echo "您可以使用yum命令安装所需软件包了"
