#!/bin/bash

# [大锤sand-box] 配置生成模块 (Final Expert Version)
# 支持"独立固定出口模式"，专为注册机设计

source ./core.sh
source ./warp_pool.sh

SB_CONFIG_DIR="/etc/hammer-sb"
BASE_CONF="$SB_CONFIG_DIR/base_config.json"

# 参数初始化
uuid=$(cat /proc/sys/kernel/random/uuid)
fetch_ip() { export pub_ip=$(curl -s4m3 icanhazip.com || echo "您的IP"); }

# 生成密钥对 (复用)
gen_keys() {
    rkp=$($SB_BINARY_PATH generate reality-keypair 2>/dev/null)
    # 兼容多种输出格式: "Private key: xxx" 或 JSON
    if echo "$rkp" | jq -e . >/dev/null 2>&1; then
        priv_key=$(echo "$rkp" | jq -r '.private_key // .privateKey // empty')
        pub_key=$(echo "$rkp" | jq -r '.public_key // .publicKey // empty')
    fi
    if [[ -z "$priv_key" ]]; then
        priv_key=$(echo "$rkp" | grep -i "private" | awk '{print $NF}')
    fi
    if [[ -z "$pub_key" ]]; then
        pub_key=$(echo "$rkp" | grep -i "public" | awk '{print $NF}')
    fi
    short_id=$(openssl rand -hex 8)
}

# 构建五协议入站 JSON (共享出口，走 WARP 池 selector)
build_five_protocols() {
    local port_base=$1
    local keys_priv=$2
    local keys_pub=$3
    local keys_sid=$4
    local user_uuid=$5

    cat <<INEOF
    { "type": "vless", "tag": "in-vl", "listen": "::", "listen_port": $((port_base)), "users": [{ "uuid": "$user_uuid", "flow": "xtls-rprx-vision" }], "tls": { "enabled": true, "server_name": "apple.com", "reality": { "enabled": true, "handshake": { "server": "apple.com", "server_port": 443 }, "private_key": "$keys_priv", "short_id": ["$keys_sid"] } } },
    { "type": "vmess", "tag": "in-vm", "listen": "::", "listen_port": $((port_base+1)), "users": [{ "uuid": "$user_uuid", "alterId": 0 }], "transport": { "type": "ws", "path": "/hammer-vm" } },
    { "type": "hysteria2", "tag": "in-hy", "listen": "::", "listen_port": $((port_base+2)), "users": [{ "password": "$user_uuid" }], "tls": { "enabled": true, "server_name": "www.bing.com", "certificate_path": "/etc/hammer-sb/cert.pem", "key_path": "/etc/hammer-sb/key.pem" } },
    { "type": "tuic", "tag": "in-tc", "listen": "::", "listen_port": $((port_base+3)), "users": [{ "uuid": "$user_uuid", "password": "$user_uuid" }], "tls": { "enabled": true, "server_name": "www.bing.com", "certificate_path": "/etc/hammer-sb/cert.pem", "key_path": "/etc/hammer-sb/key.pem" } },
    { "type": "anytls", "tag": "in-an", "listen": "::", "listen_port": $((port_base+4)), "users": [{ "name": "user", "password": "$user_uuid" }], "tls": { "enabled": true, "server_name": "www.bing.com", "certificate_path": "/etc/hammer-sb/cert.pem", "key_path": "/etc/hammer-sb/key.pem" } }
INEOF
}

# 构建 N 路 WARP 专属 VLESS 入站 (每路直连固定 WARP 出口)
build_warp_direct_inbounds() {
    local port_base=$1
    local pool_size=$2
    local keys_priv=$3
    local user_uuid=$4

    local result=""
    for i in $(seq 1 $pool_size); do
        local sid=$(openssl rand -hex 8)
        local p=$((port_base + i - 1))
        result+="    { \"type\": \"vless\", \"tag\": \"in-warp$i\", \"listen\": \"::\", \"listen_port\": $p, \"users\": [{ \"uuid\": \"$user_uuid\", \"flow\": \"xtls-rprx-vision\" }], \"tls\": { \"enabled\": true, \"server_name\": \"apple.com\", \"reality\": { \"enabled\": true, \"handshake\": { \"server\": \"apple.com\", \"server_port\": 443 }, \"private_key\": \"$keys_priv\", \"short_id\": [\"$sid\"] } } }"
        [[ $i -lt $pool_size ]] && result+=","
        result+=$'\n'
    done
    echo "$result"
}

# 构建 WARP 直连路由规则
build_warp_direct_rules() {
    local pool_size=$1
    local result=""
    for i in $(seq 1 $pool_size); do
        result+="      { \"inbound\": [\"in-warp$i\"], \"outbound\": \"warp-pool-$i\" }"
        [[ $i -lt $pool_size ]] && result+=","
        result+=$'\n'
    done
    echo "$result"
}

generate_config() {
    log_info "正在启动大锤 [专家模式] 配置生成..."
    mkdir -p "$SB_CONFIG_DIR"

    read -p "设置 WARP 独立出口数量 (1-10, 默认3): " pool_size
    pool_size=${pool_size:-3}

    read -p "是否通过 Psiphon 指定出口国家？(如 US, JP, SG, 留空为原生): " country_code
    country_code=$(echo "$country_code" | tr '[:lower:]' '[:upper:]')

    echo ""
    echo -e "${yellow}域名分流配置 (哪些域名走 WARP，其余直连):${plain}"
    read -p "输入分流域名，多个用逗号分隔 (如 google.com,openai.com, 留空则全部走WARP): " warp_domains

    gen_keys

    # 五协议入站 (端口从 60001 开始，每协议间隔5)
    local shared_inbounds=$(build_five_protocols 60001 "$priv_key" "$pub_key" "$short_id" "$uuid")

    # WARP 直连入站 (端口从 61001 开始)
    local warp_inbounds=""
    local warp_rules=""
    if [[ $pool_size -gt 0 ]]; then
        warp_inbounds=$(build_warp_direct_inbounds 61001 "$pool_size" "$priv_key" "$uuid")
        warp_rules=$(build_warp_direct_rules "$pool_size")
    fi

    # 所有协议入站路由到 WARP 池 selector
    pool_tags=""
    for i in $(seq 1 $pool_size); do
        pool_tags+="\"warp-pool-$i\","
    done
    pool_tags=${pool_tags%,}

    # 构建域名分流规则
    local domain_rule=""
    if [[ -n "$warp_domains" ]]; then
        # 将逗号分隔的域名转为 JSON 数组
        local domain_json=$(echo "$warp_domains" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R . | jq -sc .)
        domain_rule="      { \"domain\": $domain_json, \"outbound\": \"Warp-Pool\" },
      { \"domain\": $domain_json, \"outbound\": \"Warp-Pool\" },"
    fi

    cat > "$BASE_CONF" <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
$shared_inbounds
$([[ -n "$warp_inbounds" ]] && echo "$warp_inbounds")
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" },
    { "type": "selector", "tag": "Warp-Pool", "outbounds": [$pool_tags] }
  ],
  "route": {
    "rules": [
      { "inbound": ["in-vl","in-vm","in-hy","in-tc","in-an"], "outbound": "Warp-Pool" },
      { "protocol": "dns", "action": "sniff" },
$([[ -n "$domain_rule" ]] && echo "$domain_rule")
$([[ -n "$warp_rules" ]] && echo "$warp_rules")
      { "rule_set": ["geosite-cn"], "outbound": "direct" },
      { "rule_set": ["geoip-cn"], "outbound": "direct" }
    ],
    "rule_set": [
      { "type": "remote", "tag": "geosite-cn", "format": "binary", "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs", "download_detour": "direct" },
      { "type": "remote", "tag": "geoip-cn", "format": "binary", "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs", "download_detour": "direct" }
    ],
    "final": "direct",
    "auto_detect_interface": true
  },
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "/etc/hammer-sb/cache.db"
    },
    "clash_api": {
      "external_controller": "0.0.0.0:9090",
      "external_ui": "/etc/hammer-sb/ui"
    }
  }
}
EOF

    # 证书与池子初始化
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /etc/hammer-sb/key.pem -out /etc/hammer-sb/cert.pem -days 3650 -subj "/CN=www.bing.com" >/dev/null 2>&1
    generate_warp_pool "$pool_size" "$country_code"
    bash ./re-assemble.sh

    # 打印报告
    fetch_ip
    local c_addr=$(get_client_addr)
    local c_p1=$(get_client_port 60001)
    local c_p2=$(get_client_port 60002)
    local c_p3=$(get_client_port 60003)
    local c_p4=$(get_client_port 60004)
    local c_p5=$(get_client_port 60005)
    log_info "配置完成！"
    echo -e "${blue}======================================${plain}"
    echo -e "${green}   大锤-已为您开通 5 协议 + $pool_size 路 WARP 直连     ${plain}"
    echo -e "${blue}======================================${plain}"
    echo -e "${yellow}--- 共享出口 (5协议 → WARP池自动选择) ---${plain}"
    echo -e "Vless-Reality: ${yellow}vless://$uuid@$c_addr:$c_p1?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$pub_key&sid=$short_id&type=tcp#大锤-VL${plain}"
    echo -e "Vmess-WS:      ${yellow}vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"大锤-VM\",\"add\":\"$c_addr\",\"port\":\"$c_p2\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/hammer-vm\"}" | base64 | tr -d '\n')${plain}"
    echo -e "Hysteria2:     ${yellow}hysteria2://$uuid@$c_addr:$c_p3?security=tls&sni=www.bing.com#大锤-HY${plain}"
    echo -e "Tuic v5:       ${yellow}tuic://$uuid:$uuid@$c_addr:$c_p4?sni=www.bing.com&congestion_control=bbr#大锤-TC${plain}"
    echo -e "AnyTLS:        ${yellow}anytls://user:$uuid@$c_addr:$c_p5?sni=www.bing.com#大锤-AN${plain}"

    # 打印 WARP 直连节点
    if [[ $pool_size -gt 0 ]]; then
        echo -e ""
        echo -e "${yellow}--- WARP 直连节点 (每路固定出口) ---${plain}"
        for i in $(seq 1 $pool_size); do
            local sid_i=$(jq -r ".inbounds[] | select(.tag==\"in-warp$i\") | .tls.reality.short_id[0]" "$BASE_CONF" 2>/dev/null || echo "xxxxxxxx")
            local c_p=$(get_client_port $((61000 + i)))
            echo -e "WARP出口$i: ${yellow}vless://$uuid@$c_addr:$c_p?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$pub_key&sid=$sid_i&type=tcp#大锤-WARP$i${plain}"
        done
    fi

    echo -e "${blue}======================================${plain}"
    if [[ -n "$warp_domains" ]]; then
        echo -e "域名分流: ${yellow}${warp_domains}${plain} → WARP，其余 → 直连"
    else
        echo -e "分流模式: 全部流量走 WARP 池"
    fi
    [[ "$c_addr" != "$pub_ip" ]] && echo -e "客户端地址映射: ${yellow}${c_addr}${plain} (公网IP: ${pub_ip})"
}

# 静默配置重生成 (从 protocols.conf 读取状态，无交互)
generate_config_silent() {
    local pf="/etc/hammer-sb/protocols.conf"
    if [[ ! -f "$pf" ]]; then
        log_error "协议状态文件不存在，无法静默重载。"
        return 1
    fi
    if [[ ! -f "$BASE_CONF" ]]; then
        log_error "基础配置文件不存在，请先执行全量初始化。"
        return 1
    fi

    log_info "正在根据协议状态静默重组配置..."

    # 读取当前配置中的入站列表
    local config="/etc/hammer-sb/config.json"
    local vl=$(grep '^VL=' "$pf" | cut -d= -f2)
    local vm=$(grep '^VM=' "$pf" | cut -d= -f2)
    local hy=$(grep '^HY=' "$pf" | cut -d= -f2)
    local tc=$(grep '^TC=' "$pf" | cut -d= -f2)
    local an=$(grep '^AN=' "$pf" | cut -d= -f2)

    # 用 jq 按协议状态过滤入站 (关闭的协议移除对应入站)
    # 入站 tag 命名约定: in-vl, in-vm, in-hy, in-tc, in-an
    local disabled_tags=()
    [[ "$vl" == "0" ]] && disabled_tags+=("in-vl")
    [[ "$vm" == "0" ]] && disabled_tags+=("in-vm")
    [[ "$hy" == "0" ]] && disabled_tags+=("in-hy")
    [[ "$tc" == "0" ]] && disabled_tags+=("in-tc")
    [[ "$an" == "0" ]] && disabled_tags+=("in-an")

    if [[ ${#disabled_tags[@]} -eq 0 ]]; then
        # 全部开启，直接重载
        systemctl reload hammer-sb 2>/dev/null || systemctl start hammer-sb
        log_info "全部协议已开启，已热重载。"
        return 0
    fi

    # 构建 jq 过滤表达式: 移除 tag 在 disabled 列表中的入站
    local filter=""
    for t in "${disabled_tags[@]}"; do
        filter+=" .tag != \"$t\" and"
    done
    filter="${filter% and}"

    jq ".inbounds = [.inbounds[] | select($filter)]" "$config" > "${config}.tmp"
    if [[ $? -eq 0 ]]; then
        mv "${config}.tmp" "$config"
        systemctl reload hammer-sb 2>/dev/null || systemctl start hammer-sb
        log_info "协议配置已更新并热重载。"
    else
        rm -f "${config}.tmp"
        log_error "配置重组失败。"
    fi
}
