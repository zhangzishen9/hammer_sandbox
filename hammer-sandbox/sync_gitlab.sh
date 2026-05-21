#!/bin/bash

# [大锤sand-box] 万能订阅管理模块 (Final Production Version)
# 实现全平台(Clash/Singbox/Generic)同步推送，含五协议+WARP直连全量导出

source ./core.sh

SB_CONFIG_DIR="/etc/hammer-sb"
SB_CONF="$SB_CONFIG_DIR/config.json"
GIST_TOKEN_FILE="$SB_CONFIG_DIR/gist_token.conf"

# 获取动态运行参数
extract_params() {
    uuid=$(jq -r '.inbounds[] | select(.type=="vless") | .users[0].uuid' "$SB_CONF" 2>/dev/null || echo "")
    p_vl=$(jq -r '.inbounds[] | select(.tag=="in-vl") | .listen_port' "$SB_CONF" 2>/dev/null || echo "")
    p_vm=$(jq -r '.inbounds[] | select(.tag=="in-vm") | .listen_port' "$SB_CONF" 2>/dev/null || echo "")
    p_hy=$(jq -r '.inbounds[] | select(.tag=="in-hy") | .listen_port' "$SB_CONF" 2>/dev/null || echo "")
    p_tc=$(jq -r '.inbounds[] | select(.tag=="in-tc") | .listen_port' "$SB_CONF" 2>/dev/null || echo "")
    p_an=$(jq -r '.inbounds[] | select(.tag=="in-an") | .listen_port' "$SB_CONF" 2>/dev/null || echo "")
    pbk=$(jq -r '.inbounds[] | select(.type=="vless") | .tls.reality.public_key // empty' "$SB_CONF" 2>/dev/null || \
         $SB_BINARY_PATH generate reality-keypair 2>/dev/null | grep "Public key:" | awk '{print $3}')
    sid=$(jq -r '.inbounds[] | select(.tag=="in-vl") | .tls.reality.short_id[0] // empty' "$SB_CONF" 2>/dev/null || echo "ab12cd34")
    ip=$(curl -s4m5 icanhazip.com)
    # 客户端使用映射地址和映射端口
    c_ip=$(get_client_addr)
    c_p_vl=$(get_client_port "$p_vl")
    c_p_vm=$(get_client_port "$p_vm")
    c_p_hy=$(get_client_port "$p_hy")
    c_p_tc=$(get_client_port "$p_tc")
    c_p_an=$(get_client_port "$p_an")
    [[ -z "$uuid" ]] && uuid=$(jq -r '.inbounds[0].users[0].uuid' "$SB_CONF" 2>/dev/null)
    # 提取 WARP 直连入站
    warp_nodes=$(jq -c '[.inbounds[] | select(.tag | startswith("in-warp")) | {tag, port: .listen_port, sid: .tls.reality.short_id[0]}]' "$SB_CONF" 2>/dev/null || echo "[]")
    warp_count=$(echo "$warp_nodes" | jq 'length')
}

# 1. 生成 Clash Meta (Mihomo) 全协议配置
gen_clash() {
    log_info "正在生成 Mihomo (Clash) 全功能配置文件..."

    # 先写 5 协议
    cat > "$SB_CONFIG_DIR/hammer_clash.yaml" <<EOF
proxies:
  - name: 大锤-Vless
    type: vless
    server: $c_ip
    port: $c_p_vl
    uuid: $uuid
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: apple.com
    reality-opts:
      public-key: $pbk
      short-id: $sid
    client-fingerprint: chrome
  - name: 大锤-Vmess
    type: vmess
    server: $c_ip
    port: $c_p_vm
    uuid: $uuid
    alterId: 0
    cipher: auto
    udp: true
    network: ws
    ws-opts:
      path: /hammer-vm
  - name: 大锤-Hysteria2
    type: hysteria2
    server: $c_ip
    port: $c_p_hy
    password: $uuid
    sni: www.bing.com
    skip-cert-verify: true
  - name: 大锤-Tuic
    type: tuic
    server: $c_ip
    port: $c_p_tc
    uuid: $uuid
    password: $uuid
    sni: www.bing.com
    skip-cert-verify: true
    udp-relay-mode: native
    congestion-controller: bbr
  - name: 大锤-AnyTLS
    type: anytls
    server: $c_ip
    port: $c_p_an
    password: $uuid
    udp: true
    sni: www.bing.com
    skip-cert-verify: true
EOF

    # 追加 WARP 直连节点
    for i in $(seq 0 $((warp_count - 1))); do
        local w_port=$(echo "$warp_nodes" | jq -r ".[$i].port")
        local w_sid=$(echo "$warp_nodes" | jq -r ".[$i].sid")
        local w_cport=$(get_client_port "$w_port")
        local w_idx=$((i + 1))
        cat >> "$SB_CONFIG_DIR/hammer_clash.yaml" <<EOF
  - name: 大锤-WARP${w_idx}
    type: vless
    server: $c_ip
    port: $w_cport
    uuid: $uuid
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: apple.com
    reality-opts:
      public-key: $pbk
      short-id: $w_sid
    client-fingerprint: chrome
EOF
    done

    # 构建 proxy-groups 的 WARP 节点列表
    local warp_proxy_list=""
    local warp_select_list=""
    for i in $(seq 1 $warp_count); do
        warp_proxy_list+=$'\n'"      - 大锤-WARP${i}"
        warp_select_list+=$'\n'"      - 大锤-WARP${i}"
    done

    cat >> "$SB_CONFIG_DIR/hammer_clash.yaml" <<EOF

proxy-groups:
  - name: 选择代理节点
    type: select
    proxies:
      - 负载均衡
      - 自动选择
      - 大锤-Vless
      - 大锤-Vmess
      - 大锤-Hysteria2
      - 大锤-Tuic
      - 大锤-AnyTLS${warp_select_list}
      - DIRECT
  - name: 负载均衡
    type: load-balance
    strategy: round-robin
    url: http://www.gstatic.com/generate_204
    interval: 300
    proxies:
      - 大锤-Vless
      - 大锤-Vmess
      - 大锤-Hysteria2
      - 大锤-Tuic${warp_proxy_list}
  - name: 自动选择
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 300
    tolerance: 150
    proxies:
      - 大锤-Vless
      - 大锤-Vmess
      - 大锤-Hysteria2
      - 大锤-Tuic
      - 大锤-AnyTLS${warp_proxy_list}

rules:
  - GEOSITE,category-ads-all,REJECT
  - GEOIP,CN,DIRECT
  - GEOSITE,CN,DIRECT
  - MATCH,选择代理节点
EOF
}

# 2. 生成 Sing-Box 客户端配置
gen_singbox_client() {
    # 构建 WARP outbound 条目
    local warp_outbounds=""
    local warp_auto_list=""
    local warp_proxy_list=""
    for i in $(seq 0 $((warp_count - 1))); do
        local w_port=$(echo "$warp_nodes" | jq -r ".[$i].port")
        local w_sid=$(echo "$warp_nodes" | jq -r ".[$i].sid")
        local w_cport=$(get_client_port "$w_port")
        local w_idx=$((i + 1))
        warp_outbounds+="
    { \"type\": \"vless\", \"tag\": \"大锤-WARP${w_idx}\", \"server\": \"$c_ip\", \"server_port\": $w_cport,
      \"uuid\": \"$uuid\", \"flow\": \"xtls-rprx-vision\",
      \"tls\": { \"enabled\": true, \"server_name\": \"apple.com\", \"utls\": { \"enabled\": true, \"fingerprint\": \"chrome\" },
        \"reality\": { \"enabled\": true, \"public_key\": \"$pbk\", \"short_id\": \"$w_sid\" } } },"
        warp_auto_list+="\"大锤-WARP${w_idx}\","
        warp_proxy_list+="\"大锤-WARP${w_idx}\","
    done
    warp_auto_list=${warp_auto_list%,}
    warp_proxy_list=${warp_proxy_list%,}

    cat > "$SB_CONFIG_DIR/hammer_singbox_client.json" <<EOF
{
  "log": { "level": "info" },
  "outbounds": [
    {
      "type": "urltest",
      "tag": "auto",
      "outbounds": ["大锤-VL","大锤-VM","大锤-HY","大锤-TC","大锤-AN",${warp_auto_list}],
      "url": "http://www.gstatic.com/generate_204",
      "interval": "5m"
    },
    {
      "type": "selector", "tag": "proxy",
      "outbounds": ["auto","大锤-VL","大锤-VM","大锤-HY","大锤-TC","大锤-AN",${warp_proxy_list}]
    },
    { "type": "vless", "tag": "大锤-VL", "server": "$c_ip", "server_port": $c_p_vl,
      "uuid": "$uuid", "flow": "xtls-rprx-vision",
      "tls": { "enabled": true, "server_name": "apple.com", "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": { "enabled": true, "public_key": "$pbk", "short_id": "$sid" } } },
    { "type": "vmess", "tag": "大锤-VM", "server": "$c_ip", "server_port": $c_p_vm,
      "uuid": "$uuid", "transport": { "type": "ws", "path": "/hammer-vm" } },
    { "type": "hysteria2", "tag": "大锤-HY", "server": "$c_ip", "server_port": $c_p_hy,
      "password": "$uuid", "tls": { "enabled": true, "server_name": "www.bing.com", "insecure": true } },
    { "type": "tuic", "tag": "大锤-TC", "server": "$c_ip", "server_port": $c_p_tc,
      "uuid": "$uuid", "password": "$uuid",
      "tls": { "enabled": true, "server_name": "www.bing.com", "insecure": true } },
    { "type": "anytls", "tag": "大锤-AN", "server": "$c_ip", "server_port": $c_p_an,
      "password": "$uuid", "tls": { "enabled": true, "server_name": "www.bing.com", "insecure": true } },${warp_outbounds}
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [
      { "rule_set": ["geosite-cn"], "outbound": "direct" },
      { "rule_set": ["geoip-cn"], "outbound": "direct" }
    ],
    "rule_set": [
      { "type": "remote", "tag": "geosite-cn", "format": "binary", "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs", "download_detour": "direct" },
      { "type": "remote", "tag": "geoip-cn", "format": "binary", "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs", "download_detour": "direct" }
    ],
    "final": "proxy"
  }
}
EOF
}

# 3. 生成 Base64 通用订阅
gen_base64_sub() {
    local sub=""
    sub+="vless://$uuid@$c_ip:$c_p_vl?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$pbk&sid=$sid&type=tcp#大锤-VL\n"
    sub+="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"大锤-VM\",\"add\":\"$c_ip\",\"port\":\"$c_p_vm\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/hammer-vm\"}" | base64 | tr -d '\n')\n"
    sub+="hysteria2://$uuid@$c_ip:$c_p_hy?security=tls&sni=www.bing.com&insecure=1#大锤-HY\n"
    sub+="tuic://$uuid:$uuid@$c_ip:$c_p_tc?sni=www.bing.com&congestion_control=bbr&allow_insecure=1#大锤-TC\n"
    sub+="anytls://user:$uuid@$c_ip:$c_p_an?sni=www.bing.com&allow_insecure=1#大锤-AN"

    # 追加 WARP 直连节点
    for i in $(seq 0 $((warp_count - 1))); do
        local w_port=$(echo "$warp_nodes" | jq -r ".[$i].port")
        local w_sid=$(echo "$warp_nodes" | jq -r ".[$i].sid")
        local w_cport=$(get_client_port "$w_port")
        local w_idx=$((i + 1))
        sub+="\nvless://$uuid@$c_ip:$w_cport?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$pbk&sid=$w_sid&type=tcp#大锤-WARP${w_idx}"
    done

    echo -n "$sub" | base64 | tr -d '\n' > "$SB_CONFIG_DIR/hammer_base64.txt"
}

# 4. 推送到 GitHub Gist (匿名或带 token)
sync_to_gitlab() {
    extract_params

    if [[ -z "$uuid" || -z "$ip" ]]; then
        log_error "无法提取配置参数，请先执行初始化。"
        return 1
    fi

    gen_clash
    gen_singbox_client
    gen_base64_sub

    log_info "正在推送订阅到 GitHub Gist..."

    # 检查是否配置了 Gist Token
    local gist_id=""
    local gist_token=""
    if [[ -f "$GIST_TOKEN_FILE" ]]; then
        gist_token=$(cat "$GIST_TOKEN_FILE" | head -1)
        gist_id=$(cat "$GIST_TOKEN_FILE" | tail -1)
    fi

    if [[ -n "$gist_token" && -n "$gist_id" ]]; then
        # 使用 GitHub API 更新 Gist
        local clash_content=$(cat "$SB_CONFIG_DIR/hammer_clash.yaml" | jq -Rs .)
        local sb_content=$(cat "$SB_CONFIG_DIR/hammer_singbox_client.json" | jq -Rs .)
        local b64_content=$(cat "$SB_CONFIG_DIR/hammer_base64.txt" | jq -Rs .)

        local update_resp=$(curl -s -X PATCH "https://api.github.com/gists/$gist_id" \
            -H "Authorization: Bearer $gist_token" \
            -H "Content-Type: application/json" \
            -d "{
                \"files\": {
                    \"hammer_clash.yaml\": { \"content\": $clash_content },
                    \"hammer_singbox.json\": { \"content\": $sb_content },
                    \"hammer_base64.txt\": { \"content\": $b64_content }
                }
            }")

        local gist_url=$(echo "$update_resp" | jq -r '.html_url // empty')
        if [[ -n "$gist_url" ]]; then
            log_info "Gist 更新成功！"
            echo -e "${blue}======================================${plain}"
            echo -e "${green}   三合一订阅已推送至 GitHub Gist    ${plain}"
            echo -e "${blue}======================================${plain}"
            echo -e "订阅主页:   ${yellow}$gist_url${plain}"
            echo -e "Clash 订阅: ${yellow}${gist_url}/raw/hammer_clash.yaml${plain}"
            echo -e "SB 订阅:    ${yellow}${gist_url}/raw/hammer_singbox.json${plain}"
            echo -e "Base64 订阅: ${yellow}${gist_url}/raw/hammer_base64.txt${plain}"
            echo -e "${blue}======================================${plain}"
        else
            log_error "Gist 更新失败，请检查 Token 是否有效。"
            log_error "API 响应: $update_resp"
            print_local_paths
        fi
    else
        log_warn "未配置 GitHub Gist Token，订阅文件已生成到本地。"
        read -p "是否配置 Gist Token 以实现自动推送？(y/N): " cfg
        if [[ "$cfg" == "y" || "$cfg" == "Y" ]]; then
            read -p "输入 GitHub Personal Access Token (需 gist 权限): " gist_token
            if [[ -n "$gist_token" ]]; then
                # 自动创建 Gist
                local clash_content=$(cat "$SB_CONFIG_DIR/hammer_clash.yaml" | jq -Rs .)
                local create_resp=$(curl -s -X POST "https://api.github.com/gists" \
                    -H "Authorization: Bearer $gist_token" \
                    -H "Content-Type: application/json" \
                    -d "{
                        \"description\": \"大锤sand-box 三合一订阅\",
                        \"public\": false,
                        \"files\": {
                            \"hammer_clash.yaml\": { \"content\": $clash_content }
                        }
                    }")
                gist_id=$(echo "$create_resp" | jq -r '.id // empty')
                if [[ -n "$gist_id" ]]; then
                    echo "$gist_token" > "$GIST_TOKEN_FILE"
                    echo "$gist_id" >> "$GIST_TOKEN_FILE"
                    chmod 600 "$GIST_TOKEN_FILE"
                    log_info "Gist 已创建，正在完成首次全量推送..."
                    sync_to_gitlab
                    return
                else
                    log_error "Gist 创建失败: $create_resp"
                fi
            fi
        fi
        print_local_paths
    fi
}

print_local_paths() {
    echo -e "${blue}======================================${plain}"
    echo -e "订阅文件已保存至本地:"
    echo -e "  Clash:  ${yellow}$SB_CONFIG_DIR/hammer_clash.yaml${plain}"
    echo -e "  SB:     ${yellow}$SB_CONFIG_DIR/hammer_singbox_client.json${plain}"
    echo -e "  Base64: ${yellow}$SB_CONFIG_DIR/hammer_base64.txt${plain}"
    echo -e "${blue}======================================${plain}"
}
