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
    local_script_ver="v1.2.0"
    remote_script_ver=$(curl -s4m3 "https://raw.githubusercontent.com/zhangzishen9/dashui-sandbox/main/version.txt" | head -n 1 || echo "$local_script_ver")

    # 2. Sing-Box 内核版本
    if [[ -f "$SB_BINARY_PATH" ]]; then
        local_sb_ver=$($SB_BINARY_PATH version 2>/dev/null | awk 'NR==1 {print $3}')
    else
        local_sb_ver="未安装"
    fi
    # 真实 GitHub API 获取最新 Release
    remote_sb_ver=$(curl -s4m3 "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r .tag_name | sed 's/v//' || echo "N/A")
}

QUOTA_CONF="/etc/hammer-sb/quota.conf"
USAGE_FILE="/etc/hammer-sb/usage.db"
ADDR_MAP_CONF="/etc/hammer-sb/addr_map.conf"

# 地址映射: 用于 NAT/VM 环境下客户端使用外部地址连接
# 配置文件格式:
#   MAP_ADDR=worker-0d9c266d.dsx-air.nvidia.com  (外部IP或域名)
#   MAP_PORTS=60001:50001,60002:50002,60003:50003  (内部端口:外部端口, 可选)

# 获取客户端应使用的地址 (映射地址 > 公网IP)
get_client_addr() {
    if [[ -f "$ADDR_MAP_CONF" ]]; then
        local map_addr=$(grep '^MAP_ADDR=' "$ADDR_MAP_CONF" | cut -d= -f2-)
        if [[ -n "$map_addr" ]]; then
            echo "$map_addr"
            return
        fi
    fi
    echo "${pub_ip:-$(curl -s4m3 icanhazip.com || echo '127.0.0.1')}"
}

# 获取客户端应使用的端口 (内部端口 -> 映射端口)
# 用法: get_client_port <内部端口>
get_client_port() {
    local local_port="$1"
    if [[ -f "$ADDR_MAP_CONF" ]]; then
        local map_ports=$(grep '^MAP_PORTS=' "$ADDR_MAP_CONF" | cut -d= -f2-)
        if [[ -n "$map_ports" ]]; then
            local mapped=$(echo "$map_ports" | tr ',' '\n' | grep "^${local_port}:" | cut -d: -f2)
            if [[ -n "$mapped" ]]; then
                echo "$mapped"
                return
            fi
        fi
    fi
    echo "$local_port"
}

# 设置地址映射
set_addr_map() {
    local old_addr=""
    local old_ports=""
    if [[ -f "$ADDR_MAP_CONF" ]]; then
        old_addr=$(grep '^MAP_ADDR=' "$ADDR_MAP_CONF" | cut -d= -f2-)
        old_ports=$(grep '^MAP_PORTS=' "$ADDR_MAP_CONF" | cut -d= -f2-)
    fi

    echo -e "${blue}======================================${plain}"
    echo -e "${green}   地址映射配置 (NAT/VM 环境使用)     ${plain}"
    echo -e "${blue}======================================${plain}"
    echo -e "当前公网IP: ${yellow}${v4:-N/A}${plain}"
    [[ -n "$old_addr" ]] && echo -e "当前映射地址: ${yellow}${old_addr}${plain}"
    [[ -n "$old_ports" ]] && echo -e "当前端口映射: ${yellow}${old_ports}${plain}"
    echo -e "${blue}--------------------------------------${plain}"

    read -p "输入外部访问地址 (IP或域名, 留空清除映射): " new_addr
    if [[ -z "$new_addr" ]]; then
        rm -f "$ADDR_MAP_CONF"
        log_info "地址映射已清除，客户端将使用公网IP。"
        return
    fi

    local new_ports=""
    read -p "输入端口映射 (格式 内部端口:外部端口, 多个用逗号分隔, 留空则端口不变): " new_ports

    mkdir -p /etc/hammer-sb
    cat > "$ADDR_MAP_CONF" <<EOF
MAP_ADDR=$new_addr
MAP_PORTS=$new_ports
EOF
    chmod 600 "$ADDR_MAP_CONF"

    log_info "地址映射已设置: 客户端将使用 ${new_addr} 连接。"
    [[ -n "$new_ports" ]] && log_info "端口映射: ${new_ports}"
}

# 初始化配额文件
init_quota() {
    if [[ ! -f "$QUOTA_CONF" ]]; then
        cat > "$QUOTA_CONF" <<EOF
TOTAL_GB=500
RESET_DAY=1
EOF
    fi
    source "$QUOTA_CONF"
    TOTAL_GB=${TOTAL_GB:-500}
    RESET_DAY=${RESET_DAY:-1}
    if [[ ! -f "$USAGE_FILE" ]]; then
        echo "MONTH=0" > "$USAGE_FILE"
        echo "DOWN_BYTES=0" >> "$USAGE_FILE"
        echo "UP_BYTES=0" >> "$USAGE_FILE"
        echo "SESSION_OFFSET_DOWN=0" >> "$USAGE_FILE"
        echo "SESSION_OFFSET_UP=0" >> "$USAGE_FILE"
        echo "LAST_API_DOWN=0" >> "$USAGE_FILE"
        echo "LAST_API_UP=0" >> "$USAGE_FILE"
    fi
}

# 流量统计 (通过 sing-box clash API，含月度配额管理)
get_traffic() {
    init_quota

    local api="http://127.0.0.1:9090/traffic"
    local resp=$(curl -sm2 "$api" 2>/dev/null || echo "")
    if [[ -z "$resp" ]]; then
        traffic_up="N/A"
        traffic_down="N/A"
        return
    fi
    local api_down=$(echo "$resp" | jq -r '.down // 0' 2>/dev/null)
    local api_up=$(echo "$resp" | jq -r '.up // 0' 2>/dev/null)
    [[ ! "$api_down" =~ ^[0-9]+$ ]] && api_down=0
    [[ ! "$api_up" =~ ^[0-9]+$ ]] && api_up=0

    # 从 usage.db 读取持久化状态
    source "$USAGE_FILE"
    local cur_month=$(date +%m)
    local prev_month=${MONTH:-0}
    local saved_down=${DOWN_BYTES:-0}
    local saved_up=${UP_BYTES:-0}
    local last_api_down=${LAST_API_DOWN:-0}
    local last_api_up=${LAST_API_UP:-0}
    local offset_down=${SESSION_OFFSET_DOWN:-0}
    local offset_up=${SESSION_OFFSET_UP:-0}

    # 月初自动重置
    if [[ "$cur_month" != "$prev_month" ]]; then
        saved_down=0
        saved_up=0
        offset_down=0
        offset_up=0
        last_api_down=0
        last_api_up=0
        log_info "新月份，流量配额已自动重置。"
    fi

    # 检测 sing-box 是否重启 (API 计数器归零)
    if (( api_down < last_api_down )); then
        # 把之前的累计写入 offset
        offset_down=$(( offset_down + last_api_down ))
        offset_up=$(( offset_up + last_api_up ))
    fi

    # 本月总用量 = 持久化保存的基准 + 当前 session 以来的增量
    local total_down=$(( saved_down + offset_down + api_down ))
    local total_up=$(( saved_up + offset_up + api_up ))
    local total_bytes=$(( total_down + total_up ))

    # 格式化显示
    if command -v bc &>/dev/null; then
        used_gb=$(echo "scale=2; $total_bytes / 1073741824" | bc)
    else
        used_gb=$(awk "BEGIN {printf \"%.2f\", $total_bytes / 1073741824}")
    fi
    remain_gb=$(awk "BEGIN {printf \"%.2f\", $TOTAL_GB - $used_gb}")
    local pct=0
    pct=$(awk "BEGIN {printf \"%.1f\", $used_gb * 100 / $TOTAL_GB}")
    [[ "$pct" =~ ^[0-9] ]] || pct=0

    traffic_up=$(awk "BEGIN {printf \"%.2f GB\", $total_up / 1073741824}")
    traffic_down=$(awk "BEGIN {printf \"%.2f GB\", $total_down / 1073741824}")
    traffic_used="${used_gb} GB"
    traffic_total="${TOTAL_GB} GB"
    traffic_remain="${remain_gb} GB"
    traffic_pct="${pct}%"
    traffic_reset_day="${RESET_DAY}号"

    # 持久化当前状态
    cat > "$USAGE_FILE" <<EOF
MONTH=$cur_month
DOWN_BYTES=$saved_down
UP_BYTES=$saved_up
SESSION_OFFSET_DOWN=$offset_down
SESSION_OFFSET_UP=$offset_up
LAST_API_DOWN=$api_down
LAST_API_UP=$api_up
EOF
}

# 保存流量 (退出或重载前调用，累加当前session到持久化)
persist_traffic() {
    local api="http://127.0.0.1:9090/traffic"
    local resp=$(curl -sm2 "$api" 2>/dev/null || echo "")
    local api_down=$(echo "$resp" | jq -r '.down // 0' 2>/dev/null)
    local api_up=$(echo "$resp" | jq -r '.up // 0' 2>/dev/null)
    [[ ! "$api_down" =~ ^[0-9]+$ ]] && api_down=0
    [[ ! "$api_up" =~ ^[0-9]+$ ]] && api_up=0

    source "$USAGE_FILE" 2>/dev/null
    local saved_down=${DOWN_BYTES:-0}
    local saved_up=${UP_BYTES:-0}
    local offset_down=${SESSION_OFFSET_DOWN:-0}
    local offset_up=${SESSION_OFFSET_UP:-0}
    local cur_month=$(date +%m)
    local prev_month=${MONTH:-0}

    if [[ "$cur_month" != "$prev_month" ]]; then
        saved_down=0; saved_up=0; offset_down=0; offset_up=0
    fi

    saved_down=$(( saved_down + offset_down + api_down ))
    saved_up=$(( saved_up + offset_up + api_up ))

    cat > "$USAGE_FILE" <<EOF
MONTH=$cur_month
DOWN_BYTES=$saved_down
UP_BYTES=$saved_up
SESSION_OFFSET_DOWN=0
SESSION_OFFSET_UP=0
LAST_API_DOWN=0
LAST_API_UP=0
EOF
}

# 一键开启 BBR (标准内核方案)
enable_bbr() {
    log_info "正在开启系统原版 BBR 加速..."

    # 加载内核模块
    modprobe tcp_bbr 2>/dev/null

    # 独立检查并写入每项配置
    if ! grep -q "^net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    fi
    if ! grep -q "^net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1

    # 验证是否真正生效
    local result=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    if [[ "$result" == "bbr" ]]; then
        log_info "BBR 开启成功。"
    else
        log_warn "BBR 未生效，当前拥塞算法: ${result:-N/A}，请检查内核版本 (需 >= 4.9)"
    fi
}
