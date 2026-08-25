#!/bin/bash

# [大锤sand-box] 一键安装引导脚本 (Installation Entry)

red='\033[31m\033[01m'
green='\033[32m\033[01m'
yellow='\033[33m\033[01m'
blue='\033[36m\033[01m'
plain='\033[0m'

echo -e "${blue}======================================${plain}"
echo -e "       ${blue}正在初始化：大锤sand-box 🔨${plain}        "
echo -e "${blue}======================================${plain}"

# 1. 环境准备
if [[ $EUID -ne 0 ]]; then
   echo -e "${red}错误：请使用 root 权限运行此脚本！${plain}"
   exit 1
fi

# 确保基础工具存在
apt update -y && apt install -y wget curl jq nftables openssl python3 python3-pip python3-cryptography bc

# 升级时清理已移除的旧 Web UI 后台与定时任务。
if [[ -f /tmp/hammer-actiond.pid ]]; then
    old_web_pid=$(cat /tmp/hammer-actiond.pid 2>/dev/null)
    [[ "$old_web_pid" =~ ^[0-9]+$ ]] && kill "$old_web_pid" 2>/dev/null || true
    rm -f /tmp/hammer-actiond.pid
fi
crontab -l 2>/dev/null | grep -v "hammer_web_state" | crontab -
rm -rf /etc/hammer-sb/ui
rm -f /etc/hammer-sb/ui_pass.conf

# 2. 拉取项目文件 (此处假设托管路径，用户可自行更新)
INSTALL_PATH="/root/hammer-sandbox"
echo -e "${yellow}正在准备安装目录...${plain}"
mkdir -p "$INSTALL_PATH"

# 逻辑：下载所有核心脚本文件
BASE_URL="https://raw.githubusercontent.com/zhangzishen9/hammer_sandbox/main/hammer-sandbox"
scripts=("menu.sh" "core.sh" "install_sb.sh" "config_gen.sh" "warp_pool.sh" "warp_rotate.sh" "re-assemble.sh" "protocol_manager.sh" "hammer_bench.sh" "subscription_server.sh" "subscription_manager.py")

for s in "${scripts[@]}"; do
    echo -e "正在拉取 $s..."
    if ! wget -qO "$INSTALL_PATH/$s.tmp" "$BASE_URL/$s" || [[ ! -s "$INSTALL_PATH/$s.tmp" ]]; then
        rm -f "$INSTALL_PATH/$s.tmp"
        echo -e "${red}下载 $s 失败，安装已中止。${plain}"
        exit 1
    fi
    mv "$INSTALL_PATH/$s.tmp" "$INSTALL_PATH/$s"
done

chmod +x "$INSTALL_PATH"/*.sh

# 3. 初始安装 (注册快捷指令与服务)
cd "$INSTALL_PATH"
# 执行 menu.sh 中的初始化逻辑
bash ./menu.sh
