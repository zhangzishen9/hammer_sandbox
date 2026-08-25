#!/bin/bash

# 只读 Token 订阅服务。管理动作仅能在本机菜单执行。
SUB_DB="/etc/hammer-sb/subscriptions.json"
SUB_PORT=16000
SUB_BIND="0.0.0.0"

init_subscriptions() {
    mkdir -p /etc/hammer-sb
    [[ -s "$SUB_DB" ]] || echo '[]' > "$SUB_DB"
    chmod 600 "$SUB_DB"
}

create_subscription() {
    init_subscriptions
    [[ -f /etc/hammer-sb/config.json && -x /usr/local/bin/sing-box ]] || { log_error "请先安装 Sing-box 并初始化协议配置。"; return 1; }
    [[ -x /usr/local/bin/hammer-stats ]] || { log_error "当前内核不支持用户统计，请先执行选项1安装/更新 Sing-box。"; return 1; }
    read -p "订阅名称: " sub_name
    [[ -n "$sub_name" ]] || { log_error "名称不能为空。"; return 1; }
    echo "可选协议: vl,vm,hy,tc,an"
    read -p "允许协议 (逗号分隔，默认全部): " sub_protocols
    sub_protocols=${sub_protocols:-vl,vm,hy,tc,an}
    if [[ ! "$sub_protocols" =~ ^(vl|vm|hy|tc|an)(,(vl|vm|hy|tc|an))*$ ]]; then
        log_error "协议列表无效。"
        return 1
    fi
    read -p "流量配额 GB (默认500): " sub_total
    sub_total=${sub_total:-500}
    [[ "$sub_total" =~ ^[0-9]+$ ]] && [[ "$sub_total" -gt 0 ]] || { log_error "配额必须是正整数。"; return 1; }
    read -p "每月重置日 1-28 (默认1): " sub_reset_day
    sub_reset_day=${sub_reset_day:-1}
    [[ "$sub_reset_day" =~ ^[0-9]+$ ]] && (( sub_reset_day >= 1 && sub_reset_day <= 28 )) || { log_error "重置日必须为 1-28。"; return 1; }
    read -p "到期日期 YYYY-MM-DD (留空永久): " sub_expire_date
    local sub_expire=0
    if [[ -n "$sub_expire_date" ]]; then
        sub_expire=$(date -d "$sub_expire_date 23:59:59" +%s 2>/dev/null) || { log_error "日期格式无效。"; return 1; }
    fi
    local token=$(openssl rand -hex 24)
    local credential=$(cat /proc/sys/kernel/random/uuid)
    local short_id=$(openssl rand -hex 8)
    local server=$(get_client_addr)
    local protocols_json=$(printf '%s' "$sub_protocols" | tr ',' '\n' | jq -R . | jq -s .)
    local total_bytes=$((sub_total * 1073741824))
    jq --arg token "$token" --arg name "$sub_name" --arg credential "$credential" --arg sid "$short_id" --arg server "$server" \
       --argjson protocols "$protocols_json" \
       --argjson total "$total_bytes" --argjson expire "$sub_expire" --argjson reset_day "$sub_reset_day" \
       '. += [{token:$token,name:$name,credential:$credential,short_id:$sid,server:$server,protocols:$protocols,total_bytes:$total,expire:$expire,reset_day:$reset_day,enabled:true,upload_bytes:0,download_bytes:0,used_bytes:0}]' \
       "$SUB_DB" > "$SUB_DB.tmp" && mv "$SUB_DB.tmp" "$SUB_DB"
    chmod 600 "$SUB_DB"
    local addr=$(get_client_addr)
    log_info "订阅地址: http://${addr}:${SUB_PORT}/sub/${token}"
    log_info "所有订阅共享主协议端口，只需额外放行订阅服务 TCP 16000。"
    log_warn "这是 HTTP 链接，订阅内容和 Token 在传输途中不加密；请只发给可信用户。"
    log_info "正在同步独立用户配置并启动订阅服务..."
    install_subscription_service || {
        log_error "订阅已创建，但服务启动失败，请检查 systemctl status hammer-sub。"
        return 1
    }
}

list_subscriptions() {
    init_subscriptions
    jq -r '.[] | "名称=\(.name)  协议=\(.protocols|join(","))  已用=\(.used_bytes/1073741824*100|floor/100)GB/\(.total_bytes/1073741824|floor)GB  每月\(.reset_day // 1)号重置  到期=\(if .expire==0 then "永久" else (.expire|todate) end)  状态=\(if .active_runtime then "生效" elif .enabled then "到期或超额" else "停用" end)\n地址=http://\(.server):16000/sub/\(.token)"' "$SUB_DB"
}

revoke_subscription() {
    init_subscriptions
    read -p "输入要停用的 Token: " token
    jq --arg token "$token" 'map(if .token==$token then .enabled=false else . end)' "$SUB_DB" > "$SUB_DB.tmp" && mv "$SUB_DB.tmp" "$SUB_DB"
    chmod 600 "$SUB_DB"
    python3 /etc/hammer-sb/subscription_manager.py reconcile || return 1
    log_info "订阅及服务端凭据已停用，旧客户端配置将无法继续连接。"
}

install_subscription_service() {
    init_subscriptions
    [[ -f /etc/hammer-sb/config.json && -x /usr/local/bin/sing-box ]] || {
        log_error "请先安装 Sing-box 并初始化协议配置。"
        return 1
    }
    [[ -x /usr/local/bin/hammer-stats ]] || { log_error "当前内核不支持用户统计，请先执行选项1安装/更新 Sing-box。"; return 1; }
    local service_changed=0
    local source_dir="${SCRIPT_DIR:-$(pwd)}"
    if ! cmp -s "$source_dir/subscription_server.sh" /etc/hammer-sb/subscription_server.sh; then
        cp "$source_dir/subscription_server.sh" /etc/hammer-sb/subscription_server.sh || return 1
        service_changed=1
    fi
    if ! cmp -s "$source_dir/subscription_manager.py" /etc/hammer-sb/subscription_manager.py; then
        cp "$source_dir/subscription_manager.py" /etc/hammer-sb/subscription_manager.py || return 1
        service_changed=1
    fi
    chmod 700 /etc/hammer-sb/subscription_server.sh
    chmod 700 /etc/hammer-sb/subscription_manager.py
    nft delete table inet hammer_sub >/dev/null 2>&1 || true
    local manager_hash=$(sha256sum /etc/hammer-sb/subscription_manager.py | awk '{print $1}')
    local unit_tmp="/tmp/hammer-sub.service.$$"
    cat > "$unit_tmp" <<EOF
[Unit]
Description=Hammer read-only subscription service
After=network.target hammer-sb.service

[Service]
User=root
Environment=HAMMER_SUB_CODE_SHA256=${manager_hash}
ExecStart=/usr/bin/python3 /etc/hammer-sb/subscription_manager.py serve ${SUB_PORT}
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/etc/hammer-sb

[Install]
WantedBy=multi-user.target
EOF
    if ! cmp -s "$unit_tmp" /etc/systemd/system/hammer-sub.service; then
        install -m 644 "$unit_tmp" /etc/systemd/system/hammer-sub.service || { rm -f "$unit_tmp"; return 1; }
        service_changed=1
    fi
    rm -f "$unit_tmp"
    python3 /etc/hammer-sb/subscription_manager.py reconcile || return 1
    (( service_changed == 1 )) && systemctl daemon-reload
    systemctl enable hammer-sub || return 1
    if (( service_changed == 1 )) || ! systemctl is-active --quiet hammer-sub; then
        systemctl restart hammer-sub || return 1
    fi
    log_info "只读订阅服务已启动: ${SUB_BIND}:${SUB_PORT}。"
}

manage_subscriptions() {
    while true; do
        echo -e "${blue}================ 独立订阅管理 ================${plain}"
        echo "1. 创建订阅（协议组合/配额/到期时间）"
        echo "2. 查看订阅"
        echo "3. 停用订阅并撤销节点"
        echo "4. 手动重启订阅服务"
        echo "0. 返回"
        read -p "请选择: " sub_choice
        case "$sub_choice" in
            1) create_subscription; read -p "按回车继续..." ;;
            2) list_subscriptions; read -p "按回车继续..." ;;
            3) revoke_subscription; read -p "按回车继续..." ;;
            4) install_subscription_service; read -p "按回车继续..." ;;
            0) return ;;
        esac
    done
}

serve_subscriptions() {
    exec python3 /etc/hammer-sb/subscription_manager.py serve "$SUB_PORT"
}

if [[ "${BASH_SOURCE[0]}" == "$0" && "${1:-}" == "serve" ]]; then
    serve_subscriptions
fi
