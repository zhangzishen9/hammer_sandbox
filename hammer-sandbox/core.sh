#!/bin/bash

# [大锤sand-box] 核心函数库 (The Hardcore Core)
# 包含视觉 UI、硬件检测、内核/脚本版本实时监控

SB_BINARY_PATH="/usr/local/bin/sing-box"
SB_CONFIG_DIR="/etc/hammer-sb"

# 颜色
red='\033[31m\033[01m'
green='\033[32m\033[01m'
yellow='\033[33m\033[01m'
blue='\033[36m\033[01m'
plain='\033[0m'

log_info() { echo -e "${green}[INFO]${plain} $1"; }
log_warn() { echo -e "${yellow}[WARN]${plain} $1"; }
log_error() { echo -e "${red}[ERROR]${plain} $1"; }

# 系统环境检测
detect_os() {
    if [[ -f /etc/redhat-release ]]; then release="centos"
    elif grep -q "debian" /etc/os-release; then release="debian"
    elif grep -q "ubuntu" /etc/os-release; then release="ubuntu"
    fi
    arch=$(uname -m)
}

# 硬件与网络全息状态获取 (Hardware & Network Dashboard)
get_vps_info() {
    # 异步抓取 IP
    v4=$(curl -s4m3 icanhazip.com || echo "None")
    region=$(curl -s4m3 https://ipapi.co/json/ | jq -r '.city + ", " + .country_name' 2>/dev/null || echo "Unknown")
    
    # 系统内核与 BBR
    bbr_status=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}' || echo "N/A")
    virt=$(systemd-detect-virt 2>/dev/null || echo "kvm")
}

# 版本深度检测逻辑
check_versions() {
    # 1. 大锤脚本版本
    local_script_ver="v1.1.0"
    # 这里请求 GitHub 上的 version.txt (暂定为您之后托管的地址)
    remote_script_ver=$(curl -s4m3 "https://raw.githubusercontent.com/YourUser/dashui-sandbox/main/version.txt" | head -n 1 || echo "$local_script_ver")

    # 2. Sing-Box 内核版本
    if [[ -f "$SB_BINARY_PATH" ]]; then
        local_sb_ver=$($SB_BINARY_PATH version 2>/dev/null | awk 'NR==1 {print $3}')
    else
        local_sb_ver="未安装"
    fi
    # 真实 GitHub API 获取最新 Release
    remote_sb_ver=$(curl -s4m3 "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r .tag_name | sed 's/v//' || echo "N/A")
}

# 一键开启 BBR (标准内核方案)
enable_bbr() {
    log_info "正在开启系统原版 BBR 加速..."
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi
    log_info "BBR 开启成功。"
}
