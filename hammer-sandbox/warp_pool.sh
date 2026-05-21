#!/bin/bash

# [大锤sand-box] WARP 池化管理模块 (WARP Pooling & Rotation) - Production Version
# 包含真正的 Cloudflare API 注册逻辑

source ./core.sh

WARP_POOL_CONF="/etc/hammer-sb/warp_pool.json"

# 真正的 Cloudflare 账号注册函数 (Production API)
register_warp_account() {
    # 1. 生成客户端密钥对 (Generate Client Keypair)
    priv_key=$($SB_BINARY_PATH generate keypair | grep "Private key:" | awk '{print $3}')
    pub_key=$($SB_BINARY_PATH generate keypair | grep "Public key:" | awk '{print $3}')

    # 2. 向 Cloudflare 注册
    response=$(curl -s -X POST "https://api.cloudflareclient.com/v0a1922/reg" \
        -H "Content-Type: application/json" \
        -d "{\"key\":\"$pub_key\",\"install_id\":\"\",\"fcm_token\":\"\",\"referrer\":\"\",\"warp_enabled\":true,\"tos\":\"$(date +%FT%T%:z)\",\"type\":\"Android\",\"locale\":\"zh_CN\"}")

    # 3. 解析 ID 和 Token
    id=$(echo "$response" | jq -r .id)
    token=$(echo "$response" | jq -r .token)

    if [[ "$id" == "null" || -z "$id" ]]; then
        log_error "Cloudflare 注册失败，API 响应: $response"
        return 1
    fi

    # 4. 获取正式配置并提取 Reserved 和 IPv6 地址
    reg_detail=$(curl -s -H "Authorization: Bearer $token" \
        "https://api.cloudflareclient.com/v0a1922/reg/$id")

    # 提取客户端 IPv6 地址
    ip6=$(echo "$reg_detail" | jq -r '.config.interface.addresses.v6 // "2606:4700:d0::1"')
    # 去除 CIDR 后缀 (/128)
    ip6=${ip6%%/*}

    # 提取 Reserved 字节 (client_id 转为 reserved 数组)
    # Cloudflare API 返回的 reserved 在 config.peers[0].reserved 中
    reserved_raw=$(echo "$reg_detail" | jq -r '.config.peers[0].reserved // empty')
    if [[ -n "$reserved_raw" && "$reserved_raw" != "null" ]]; then
        res=$(echo "$reserved_raw" | jq -c .)
    else
        # 备用: 从 client_id 的 hex 编码提取 reserved 字节
        client_id=$(echo "$reg_detail" | jq -r '.client_id // empty')
        if [[ -n "$client_id" && "$client_id" != "null" ]]; then
            # 取 client_id 的前3字节转为 reserved
            hex_id=$(echo -n "$client_id" | xxd -p | head -c 6)
            if [[ -n "$hex_id" ]]; then
                b1=$((16#${hex_id:0:2}))
                b2=$((16#${hex_id:2:2}))
                b3=$((16#${hex_id:4:2}))
                res="[$b1,$b2,$b3]"
            else
                res="[0,0,0]"
            fi
        else
            res="[0,0,0]"
        fi
    fi

    echo "$priv_key,$ip6,$res"
}

# 生成 N 个 WARP Outbound 节点 (支持 Psiphon 指定国家)
# Psiphon 在 sing-box 中是独立 outbound 类型，通过 detour 链式调用 WireGuard
generate_warp_pool() {
    local pool_size=$1
    local country=$2
    log_info "正在申请 $pool_size 个全新的 Cloudflare 账号..."
    [[ -n "$country" ]] && log_info "已开启 [全球通模式]：指定出口国家为 $country"

    echo "[" > "$WARP_POOL_CONF"
    for i in $(seq 1 $pool_size); do
        acc_info=$(register_warp_account)
        [[ $? -ne 0 ]] && continue

        priv=$(echo $acc_info | cut -d',' -f1)
        ip6=$(echo $acc_info | cut -d',' -f2)
        res=$(echo $acc_info | cut -d',' -f3)

        if [[ -n "$country" ]]; then
            # 链式结构: Psiphon outbound → detour 到 WireGuard outbound
            cat >> "$WARP_POOL_CONF" <<EOF
    {
      "type": "wireguard",
      "tag": "warp-wg-$i",
      "server": "engage.cloudflareclient.com",
      "server_port": 2408,
      "local_address": ["172.16.0.2/32", "$ip6/128"],
      "private_key": "$priv",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": $res,
      "mtu": 1280
    },
    {
      "type": "psiphon",
      "tag": "warp-pool-$i",
      "server": "engage.cloudflareclient.com",
      "detour": "warp-wg-$i",
      "country": "$country"
    }$( [[ $i -lt $pool_size ]] && echo "," )
EOF
        else
            # 无 Psiphon: 直接用 WireGuard outbound
            cat >> "$WARP_POOL_CONF" <<EOF
    {
      "type": "wireguard",
      "tag": "warp-pool-$i",
      "server": "engage.cloudflareclient.com",
      "server_port": 2408,
      "local_address": ["172.16.0.2/32", "$ip6/128"],
      "private_key": "$priv",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": $res,
      "mtu": 1280
    }$( [[ $i -lt $pool_size ]] && echo "," )
EOF
        fi
        log_info "节点 warp-pool-$i 注册成功。"
    done
    echo "]" >> "$WARP_POOL_CONF"
}
