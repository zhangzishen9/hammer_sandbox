#!/bin/bash

# [大锤sand-box] 配置生成模块 (Final Expert Version)
# 支持“独立固定出口模式”，专为注册机设计

source ./core.sh
source ./warp_pool.sh

SB_CONFIG_DIR="/etc/hammer-sb"
BASE_CONF="$SB_CONFIG_DIR/base_config.json"

# 参数初始化
uuid=$(cat /proc/sys/kernel/random/uuid)
fetch_ip() { export pub_ip=$(curl -s4m3 icanhazip.com || echo "您的IP"); }

generate_config() {
    log_info "正在启动大锤 [专家模式] 配置生成..."
    mkdir -p "$SB_CONFIG_DIR"
    
    read -p "设置 WARP 独立出口数量 (1-10, 默认3): " pool_size
    pool_size=${pool_size:-3}

    read -p "是否通过 Psiphon 指定出口国家？(如 US, JP, SG, 留空为原生): " country_code
    country_code=$(echo "$country_code" | tr '[:lower:]' '[:upper:]')

    # Reality 密钥生成
    keypair=$($SB_BINARY_PATH generate reality-keypair)
    priv_key=$(echo "$keypair" | grep "Private key:" | awk '{print $3}')
    pub_key=$(echo "$keypair" | grep "Public key:" | awk '{print $3}')
    short_id=$(openssl rand -hex 8)

    # 1. 构造多端口入站与强绑定路由
    inbounds_json=""
    routing_rules_json=""
    pool_tags=""

    for i in $(seq 1 $pool_size); do
        port=$((60000 + i))
        tag="in-warp-$i"
        out_tag="warp-pool-$i"
        pool_tags+="\"$out_tag\","
        
        # 入站监听 (Vless-Reality)
        inbounds_json+="{ \"type\": \"vless\", \"tag\": \"$tag\", \"listen\": \"::\", \"listen_port\": $port, \"users\": [{ \"uuid\": \"$uuid\", \"flow\": \"xtls-rprx-vision\" }], \"tls\": { \"enabled\": true, \"server_name\": \"apple.com\", \"reality\": { \"enabled\": true, \"handshake\": { \"server\": \"apple.com\", \"server_port\": 443 }, \"private_key\": \"$priv_key\", \"short_id\": [\"$short_id\"] } } },"
        
        # 强关联路由规则 (最高优先级)
        routing_rules_json+="{ \"inbound\": [\"$tag\"], \"outbound\": \"$out_tag\" },"
    done
    inbounds_json=${inbounds_json%,}
    pool_tags=${pool_tags%,}
    routing_rules_json=${routing_rules_json}

    # 2. 写入主配置文件
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
      $routing_rules_json
      { "protocol": "dns", "outbound": "dns-out" },
      { "geosite": "cn", "geoip": "cn", "outbound": "direct" }
    ],
    "final": "direct",
    "auto_detect_interface": true
  }
}
EOF

    # 3. 证书与池子初始化
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /etc/hammer-sb/key.pem -out /etc/hammer-sb/cert.pem -days 3650 -subj "/CN=www.bing.com" >/dev/null 2>&1
    generate_warp_pool "$pool_size" "$country_code"
    bash ./re-assemble.sh
    
    # 4. 打印报告
    fetch_ip
    log_info "独立出口模式配置完成！"
    echo -e "${blue}======================================${plain}"
    echo -e "${green}   大锤-已为您开通 $pool_size 路独立物理出口     ${plain}"
    echo -e "${blue}======================================${plain}"
    for i in $(seq 1 $pool_size); do
        echo -e "物理出口-$i (端口 $((60000+i))): ${yellow}vless://$uuid@$pub_ip:$((60000+i))?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$pub_key&sid=$short_id&type=tcp#大锤-出口-$i${plain}"
    done
    echo -e "${blue}======================================${plain}"
}
