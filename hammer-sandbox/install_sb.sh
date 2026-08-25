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
            apt update -y && apt install -y wget curl jq openssl python3 bc build-essential
            ;;
        centos)
            yum install -y epel-release && yum install -y wget curl jq openssl python3 bc gcc tar
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

    if [[ "$latest_ver" == "$local_ver" && -x /usr/local/bin/hammer-stats ]]; then
        log_info "当前已是最新版本 ($local_ver)，无需更新。"
        return
    fi

    log_info "正在构建支持按用户流量统计的 Sing-Box $latest_ver（首次约需数分钟）..."
    local build_dir=$(mktemp -d /tmp/hammer-build.XXXXXX)
    local source_url="https://github.com/SagerNet/sing-box/archive/refs/tags/v${latest_ver}.tar.gz"
    wget -qO "$build_dir/source.tar.gz" "$source_url" || { log_error "下载 Sing-Box 源码失败。"; return 1; }
    tar -xzf "$build_dir/source.tar.gz" -C "$build_dir" || return 1
    local source_dir="$build_dir/sing-box-${latest_ver}"
    local go_version=$(awk '/^go / {print $2; exit}' "$source_dir/go.mod")
    local go_cpu="$cpu"
    [[ "$cpu" == "armv7" ]] && go_cpu="armv6l"
    wget -qO "$build_dir/go.tar.gz" "https://go.dev/dl/go${go_version}.linux-${go_cpu}.tar.gz" || { log_error "下载 Go $go_version 失败。"; return 1; }
    tar -xzf "$build_dir/go.tar.gz" -C "$build_dir" || return 1
    cp "${SCRIPT_DIR:-$(pwd)}/hammer_stats.go" "$source_dir/cmd/hammer-stats.go"
    local build_tags="with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_v2ray_api,badlinkname,tfogo_checklinkname0"
    local build_ldflags="-s -w -X internal/godebug.defaultGODEBUG=multipathtcp=0 -checklinkname=0"
    (cd "$source_dir" && CGO_ENABLED=0 "$build_dir/go/bin/go" build -trimpath -tags "$build_tags" -ldflags "$build_ldflags" -o "$build_dir/sing-box" ./cmd/sing-box && CGO_ENABLED=0 "$build_dir/go/bin/go" build -trimpath -tags "$build_tags" -ldflags "$build_ldflags" -o "$build_dir/hammer-stats" ./cmd/hammer-stats.go) || { log_error "自定义内核构建失败。"; return 1; }
    install -m 755 "$build_dir/sing-box" "$SB_BINARY_PATH"
    install -m 755 "$build_dir/hammer-stats" /usr/local/bin/hammer-stats
    rm -rf "$build_dir"
    if systemctl is-active --quiet hammer-sb 2>/dev/null; then
        systemctl restart hammer-sb || { log_error "新内核已安装，但 Sing-Box 重启失败。"; return 1; }
    fi
    log_info "Sing-Box $latest_ver 已安装，并启用按用户流量统计。"
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
ExecReload=-/usr/bin/python3 /etc/hammer-sb/subscription_manager.py settle
ExecReload=/bin/kill -HUP \$MAINPID
ExecStop=-/usr/bin/python3 /etc/hammer-sb/subscription_manager.py settle
ExecStop=/bin/kill -TERM \$MAINPID
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
