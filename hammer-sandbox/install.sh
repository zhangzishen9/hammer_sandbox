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
apt update -y && apt install -y wget curl git jq

# 2. 拉取项目文件 (此处假设托管路径，用户可自行更新)
INSTALL_PATH="/root/大锤sand-box"
echo -e "${yellow}正在准备安装目录...${plain}"
mkdir -p "$INSTALL_PATH"

# 逻辑：下载所有核心脚本文件
BASE_URL="https://raw.githubusercontent.com/YourUser/dashui-sandbox/main"
scripts=("menu.sh" "core.sh" "install_sb.sh" "config_gen.sh" "warp_pool.sh" "warp_rotate.sh" "re-assemble.sh" "sync_gitlab.sh" "protocol_manager.sh")

for s in "${scripts[@]}"; do
    echo -e "正在拉取 $s..."
    wget -qO "$INSTALL_PATH/$s" "$BASE_URL/$s"
done

chmod +x "$INSTALL_PATH"/*.sh

# 3. 初始安装 (注册快捷指令与服务)
cd "$INSTALL_PATH"
# 执行 menu.sh 中的初始化逻辑
bash ./menu.sh
