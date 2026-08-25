#!/bin/bash

# [大锤sand-box] 内核管理模块 (Kernel Management)
# 负责获取版本、安装及更新 Sing-Box

source ./core.sh

SB_BINARY_PATH="/usr/local/bin/sing-box"
SB_CONFIG_DIR="/etc/hammer-sb"

# 获取最新版本号 (Fetch Latest Version from GitHub)
get_latest_version() {
    log_info "正在从 GitHub 获取最新的 Sing-Box 版本..." >&2
    latest_version=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name | sed 's/v//')
    if [[ -z "$latest_version" ]]; then
        log_error "获取版本失败，请检查网络连接。" >&2
        exit 1
    fi
    echo "$latest_version"
}

# 检查本地版本 (Check Local Version)
get_local_version() {
    if [[ -f "$SB_BINARY_PATH" ]]; then
        local_version=$("$SB_BINARY_PATH" version | awk 'NR==1 {print $3}')
        echo "$local_version"
    else
        echo "none"
    fi
}

# 安装基础依赖 (Install Base Dependencies)
install_base_deps() {
    log_info "正在安装基础依赖..."
    detect_os
    case "$release" in
        ubuntu|debian)
            apt update -y && apt install -y wget curl jq nftables openssl python3 bc
            ;;
        centos)
            yum install -y epel-release && yum install -y wget curl jq nftables openssl python3 bc
            ;;
    esac
    log_info "基础依赖安装完成。"
}

# 安装或更新内核 (Install or Update Kernel)
install_kernel() {
    detect_os
    # arch → cpu 映射 (匹配 GitHub release 命名: amd64, arm64, armv7)
    case "$arch" in
        x86_64)  cpu="amd64" ;;
        aarch64) cpu="arm64" ;;
        armv7l)  cpu="armv7" ;;
        *)       cpu="unknown" ;;
    esac
    if [[ "$cpu" == "unknown" ]]; then
        log_error "不支持的架构: $arch"
        exit 1
    fi

    latest_ver=$(get_latest_version)
    local_ver=$(get_local_version)

    if [[ "$latest_ver" == "$local_ver" ]]; then
        log_info "当前已是最新版本 ($local_ver)，无需更新。"
        return
    fi

    log_info "发现新版本: $latest_ver (本地: $local_ver)，正在准备安装..."
    
    # 构造下载链接 (Construct Download URL)
    # 示例: https://github.com/SagerNet/sing-box/releases/download/v1.8.10/sing-box-1.8.10-linux-amd64.tar.gz
    download_url="https://github.com/SagerNet/sing-box/releases/download/v${latest_ver}/sing-box-${latest_ver}-linux-${cpu}.tar.gz"
    
    wget -O /tmp/sing-box.tar.gz "$download_url"
    if [[ $? -ne 0 ]]; then
        log_error "下载失败，请检查镜像源。"
        exit 1
    fi

    # 解压并替换 (Extract and Replace)
    tar -zxvf /tmp/sing-box.tar.gz -C /tmp/
    mv /tmp/sing-box-${latest_ver}-linux-${cpu}/sing-box "$SB_BINARY_PATH"
    chmod +x "$SB_BINARY_PATH"
    
    # 清理垃圾 (Cleanup)
    rm -rf /tmp/sing-box.tar.gz /tmp/sing-box-${latest_ver}-linux-${cpu}
    
    log_info "Sing-Box $latest_ver 安装完成！"
}

# 创建 Systemd 服务 (Setup Systemd Service)
setup_service() {
    log_info "正在配置 Systemd 服务..."
    mkdir -p "$SB_CONFIG_DIR"
    
    cat > /etc/systemd/system/hammer-sb.service <<EOF
[Unit]
Description=大锤sand-box Sing-Box Service
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=$SB_CONFIG_DIR
ExecStart=$SB_BINARY_PATH run -c $SB_CONFIG_DIR/config.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable hammer-sb >/dev/null 2>&1
    
    # 快捷指令注册 (Shortcut Registration)
    ln -sf "$(pwd)/menu.sh" /usr/bin/sb 2>/dev/null
    ln -sf "$(pwd)/menu.sh" /usr/bin/dc 2>/dev/null
    
    log_info "大锤sand-box 服务已就绪。您之后可以直接输入 'sb' 或 'dc' 呼出菜单。"
}

# 彻底卸载 (Full Uninstallation)
uninstall_sb() {
    log_warn "警告: 正在彻底卸载 大锤sand-box 及 Sing-Box..."
    
    # 1. 停止并禁用服务
    systemctl stop hammer-sb >/dev/null 2>&1
    systemctl disable hammer-sb >/dev/null 2>&1
    systemctl disable --now hammer-sub >/dev/null 2>&1
    rm -f /etc/systemd/system/hammer-sb.service
    rm -f /etc/systemd/system/hammer-sub.service
    systemctl daemon-reload
    
    # 2. 清理二进制文件与配置
    rm -f "$SB_BINARY_PATH"
    rm -rf "$SB_CONFIG_DIR"
    
    # 3. 清理 Cron 任务
    crontab -l 2>/dev/null | grep -v "warp_rotate.sh" | crontab -
    
    log_info "卸载完成，所有相关组件已清理。"
}
