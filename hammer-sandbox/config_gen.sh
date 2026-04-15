#!/bin/bash

# [大锤sand-box] 配置生成模块 (Config Generator) - Complete 5-Protocol Version
# 完整实现五协议: Reality, Vmess-WS, Hy2, Tuic5, AnyTLS
# 支持自定义域名分流与旧分流逻辑集成

source ./core.sh
source ./warp_pool.sh

SB_CONFIG_DIR="/etc/hammer-sb"
BASE_CONF="$SB_CONFIG_DIR/base_config.json"

# 1. 端口与参数生成
uuid=$(cat /proc/sys/kernel/random/uuid)
p_vl=$(shuf -i 10000-20000 -n 1)
p_vm=$(shuf -i 20001-30000 -n 1)
p_hy2=$(shuf -i 30001-40000 -n 1)
p_tuic=$(shuf -i 40001-50000 -n 1)
p_any=$(shuf -i 50001-65000 -n 1)

# 获取公网 IP 用于节点拼接
fetch_ip() {
    export pub_ip=$(curl -s4m5 icanhazip.com || curl -s6m5 icanhazip.com || echo "您的IP")
}

generate_config() {
    log_info "启动 大锤sand-box 灵活配置生成..."
    mkdir -p "$SB_CONFIG_DIR"
    
    # 协议开关询问 (Protocol Toggles)
    read -p "是否开启 Vless+Reality? [Y/n]: " enable_vl; enable_vl=${enable_vl:-Y}
    read -p "是否开启 Vmess+WS? [Y/n]: " enable_vm; enable_vm=${enable_vm:-Y}
    read -p "是否开启 Hysteria2? [Y/n]: " enable_hy2; enable_hy2=${enable_hy2:-Y}
    read -p "是否开启 Tuic v5? [Y/n]: " enable_tuic; enable_tuic=${enable_tuic:-Y}
    read -p "是否开启 AnyTLS? [Y/n]: " enable_any; enable_any=${enable_any:-Y}

    read -p "请输入分流到 WARP 的域名 (如 chatgpt.com netflix.com): " warp_domains
    read -p "设置 WARP 池位大小 (1-10): " pool_size
    pool_size=${pool_size:-3}

    # Reality 密钥生成
    keypair=$($SB_BINARY_PATH generate reality-keypair)
    priv_key=$(echo "$keypair" | grep "Private key:" | awk '{print $3}')
    pub_key=$(echo "$keypair" | grep "Public key:" | awk '{print $3}')
    short_id=$(openssl rand -hex 8)

    # 构造域名分流数组
    warp_json=""
    for d in $warp_domains; do warp_json+="\"$d\","; done
    warp_json=${warp_json%,}

    # 构造池子 Tag 数组
    pool_tags=""
    for i in $(seq 1 $pool_size); do pool_tags+="\"warp-pool-$i\","; done
    pool_tags=${pool_tags%,}

    # [构建 Inbounds 数组]
    inbounds_json=""
    if [[ "$enable_vl" =~ [Yy] ]]; then
        inbounds_json+="{ \"type\": \"vless\", \"tag\": \"vless-in\", \"listen\": \"::\", \"listen_port\": $p_vl, \"users\": [{ \"uuid\": \"$uuid\", \"flow\": \"xtls-rprx-vision\" }], \"tls\": { \"enabled\": true, \"server_name\": \"apple.com\", \"reality\": { \"enabled\": true, \"handshake\": { \"server\": \"apple.com\", \"server_port\": 443 }, \"private_key\": \"$priv_key\", \"short_id\": [\"$short_id\"] } } },"
    fi
    if [[ "$enable_vm" =~ [Yy] ]]; then
        inbounds_json+="{ \"type\": \"vmess\", \"tag\": \"vmess-in\", \"listen\": \"::\", \"listen_port\": $p_vm, \"users\": [{ \"uuid\": \"$uuid\", \"alterId\": 0 }], \"transport\": { \"type\": \"ws\", \"path\": \"/ws-$(echo -n $uuid | cut -d- -f1)\" } },"
    fi
    if [[ "$enable_hy2" =~ [Yy] ]]; then
        inbounds_json+="{ \"type\": \"hysteria2\", \"tag\": \"hy2-in\", \"listen\": \"::\", \"listen_port\": $p_hy2, \"users\": [{ \"password\": \"$uuid\" }], \"tls\": { \"enabled\": true, \"certificate_path\": \"/etc/hammer-sb/cert.pem\", \"key_path\": \"/etc/hammer-sb/key.pem\" } },"
    fi
    if [[ "$enable_tuic" =~ [Yy] ]]; then
        inbounds_json+="{ \"type\": \"tuic\", \"tag\": \"tuic-in\", \"listen\": \"::\", \"listen_port\": $p_tuic, \"users\": [{ \"uuid\": \"$uuid\", \"password\": \"$uuid\" }], \"congestion_control\": \"bbr\", \"tls\": { \"enabled\": true, \"certificate_path\": \"/etc/hammer-sb/cert.pem\", \"key_path\": \"/etc/hammer-sb/key.pem\", \"alpn\": [\"h3\"] } },"
    fi
    if [[ "$enable_any" =~ [Yy] ]]; then
        inbounds_json+="{ \"type\": \"anytls\", \"tag\": \"anytls-in\", \"listen\": \"::\", \"listen_port\": $p_any, \"users\": [{ \"password\": \"$uuid\" }], \"tls\": { \"enabled\": true, \"certificate_path\": \"/etc/hammer-sb/cert.pem\", \"key_path\": \"/etc/hammer-sb/key.pem\" } },"
    fi
    inbounds_json=${inbounds_json%,} # 移除拖尾逗号

    # [写入 Base Config] 
    cat > "$BASE_CONF" <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [$inbounds_json],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" },
    { "type": "dns", "tag": "dns-out" },
    { "type": "selector", "tag": "Warp-Pool", "outbounds": [$pool_tags] }
  ],
  "route": {
    "rules": [
      { "protocol": "dns", "outbound": "dns-out" },
      { "geosite": "category-ads-all", "outbound": "block" },
      { "domain": [$warp_json], "outbound": "Warp-Pool" },
      { "geosite": "cn", "geoip": "cn", "outbound": "direct" }
    ],
    "final": "direct",
    "auto_detect_interface": true
  }
}
EOF

    # 证书生成 (Hy2/Tuic/AnyTLS 共用)
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /etc/hammer-sb/key.pem -out /etc/hammer-sb/cert.pem -days 3650 -subj "/CN=www.bing.com" >/dev/null 2>&1
    
    # 触发池子初始化与组装
    generate_warp_pool $pool_size
    bash ./re-assemble.sh
    
    # 9. 打印最终报告
    fetch_ip
    log_info "五协议配置生成成功！"
    echo -e "${blue}======================================${plain}"
    echo -e "${green}   您的节点链接已生成 (纯净版)       ${plain}"
    echo -e "${blue}======================================${plain}"
    [[ "$enable_vl" =~ [Yy] ]] && echo -e "Vless-Reality: ${yellow}vless://$uuid@$pub_ip:$p_vl?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$pub_key&sid=$short_id&type=tcp#vl-reality${plain}"
    [[ "$enable_vm" =~ [Yy] ]] && echo -e "Vmess-WS: ${yellow}vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"vm-ws\",\"add\":\"$pub_ip\",\"port\":\"$p_vm\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/ws\",\"tls\":\"\"}" | base64 -w 0)${plain}"
    [[ "$enable_hy2" =~ [Yy] ]] && echo -e "Hysteria2: ${yellow}hysteria2://$uuid@$pub_ip:$p_hy2?insecure=1&sni=www.bing.com#hy2${plain}"
    [[ "$enable_tuic" =~ [Yy] ]] && echo -e "Tuic v5: ${yellow}tuic://$uuid:$uuid@$pub_ip:$p_tuic?congestion_control=bbr&alpn=h3#tuic5${plain}"
    [[ "$enable_any" =~ [Yy] ]] && echo -e "AnyTLS: ${yellow}anytls://$uuid@$pub_ip:$p_any#anytls${plain}"
    echo -e "${blue}--------------------------------------${plain}"
}
