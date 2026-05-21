#!/bin/bash
# [大锤sand-box] Web UI 状态生成器
# 每分钟 cron 执行，产出 /etc/hammer-sb/ui/api/state.json

source ./core.sh

UI_DIR="/etc/hammer-sb/ui/api"
STATE_FILE="$UI_DIR/state.json"
HISTORY_FILE="$UI_DIR/history.json"
QUOTA_CONF="/etc/hammer-sb/quota.conf"
USAGE_FILE="/etc/hammer-sb/usage.db"
PROTOCOLS_CONF="/etc/hammer-sb/protocols.conf"
WARP_POOL_CONF="/etc/hammer-sb/warp_pool.json"
SB_CONF="/etc/hammer-sb/config.json"

mkdir -p "$UI_DIR"

# ---- 流量 ----
init_quota
source "$QUOTA_CONF" 2>/dev/null
TOTAL_GB=${TOTAL_GB:-500}
RESET_DAY=${RESET_DAY:-1}

source "$USAGE_FILE" 2>/dev/null
cur_month=$(date +%m)
saved_down=${DOWN_BYTES:-0}
saved_up=${UP_BYTES:-0}
offset_down=${SESSION_OFFSET_DOWN:-0}
offset_up=${SESSION_OFFSET_UP:-0}
last_api_down=${LAST_API_DOWN:-0}
last_api_up=${LAST_API_UP:-0}

api_down=0; api_up=0
resp=$(curl -sm2 "http://127.0.0.1:9090/traffic" 2>/dev/null)
if [[ -n "$resp" ]]; then
    api_down=$(echo "$resp" | jq -r '.down // 0' 2>/dev/null)
    api_up=$(echo "$resp" | jq -r '.up // 0' 2>/dev/null)
    [[ ! "$api_down" =~ ^[0-9]+$ ]] && api_down=0
    [[ ! "$api_up" =~ ^[0-9]+$ ]] && api_up=0
fi

if [[ "$cur_month" != "${MONTH:-0}" ]]; then saved_down=0; saved_up=0; offset_down=0; offset_up=0; fi
if (( api_down < last_api_down )); then offset_down=$(( offset_down + last_api_down )); offset_up=$(( offset_up + last_api_up )); fi

total_down=$(( saved_down + offset_down + api_down ))
total_up=$(( saved_up + offset_up + api_up ))
total_bytes=$(( total_down + total_up ))

used_gb=$(awk "BEGIN {printf \"%.2f\", $total_bytes / 1073741824}")
remain_gb=$(awk "BEGIN {printf \"%.2f\", max(0, $TOTAL_GB - $used_gb)}")
pct=$(awk "BEGIN {printf \"%.1f\", $used_gb * 100 / $TOTAL_GB}")

# 保存状态供下次使用
cat > "$USAGE_FILE" <<EOF2
MONTH=$cur_month
DOWN_BYTES=$saved_down
UP_BYTES=$saved_up
SESSION_OFFSET_DOWN=$offset_down
SESSION_OFFSET_UP=$offset_up
LAST_API_DOWN=$api_down
LAST_API_UP=$api_up
EOF2

# ---- 速率估算 (与上次对比) ----
prev_down=0; prev_up=0; prev_ts=0
if [[ -f "$UI_DIR/.last_snapshot" ]]; then
    source "$UI_DIR/.last_snapshot"
fi
now_ts=$(date +%s)
down_speed=0; up_speed=0
if (( prev_ts > 0 && now_ts > prev_ts )); then
    interval=$(( now_ts - prev_ts ))
    down_speed=$(awk "BEGIN {printf \"%.2f\", ($total_down - $prev_down) / $interval}")
    up_speed=$(awk "BEGIN {printf \"%.2f\", ($total_up - $prev_up) / $interval}")
fi
cat > "$UI_DIR/.last_snapshot" <<EOF2
prev_down=$total_down
prev_up=$total_up
prev_ts=$now_ts
EOF2

# ---- 流量历史 (保留 288 条 = 24h @ 5min cron) ----
entry="{\"ts\":$now_ts,\"down\":$total_down,\"up\":$total_up}"
if [[ -f "$HISTORY_FILE" ]]; then
    jq -c --argjson e "$entry" '. += [$e] | if length > 288 then .[-288:] else . end' "$HISTORY_FILE" > "$HISTORY_FILE.tmp"
    mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
else
    echo "[$entry]" > "$HISTORY_FILE"
fi

# ---- VPS 信息 ----
detect_os
get_vps_info
check_versions

# ---- WARP 池 ----
warp_nodes="[]"
if [[ -f "$WARP_POOL_CONF" ]]; then
    warp_nodes=$(jq -c '[.[] | {tag: .tag, type: .type, server: .server, local_address: .local_address[1] // .local_address[0]}]' "$WARP_POOL_CONF" 2>/dev/null || echo "[]")
fi

# ---- 协议状态 ----
vl=1; vm=1; hy=1; tc=1; an=1
if [[ -f "$PROTOCOLS_CONF" ]]; then
    vl=$(grep '^VL=' "$PROTOCOLS_CONF" | cut -d= -f2 2>/dev/null || echo 1)
    vm=$(grep '^VM=' "$PROTOCOLS_CONF" | cut -d= -f2 2>/dev/null || echo 1)
    hy=$(grep '^HY=' "$PROTOCOLS_CONF" | cut -d= -f2 2>/dev/null || echo 1)
    tc=$(grep '^TC=' "$PROTOCOLS_CONF" | cut -d= -f2 2>/dev/null || echo 1)
    an=$(grep '^AN=' "$PROTOCOLS_CONF" | cut -d= -f2 2>/dev/null || echo 1)
fi

# ---- 订阅链接 (从 config 提取) ----
sub_links="[]"
if [[ -f "$SB_CONF" ]]; then
    ip=$(curl -s4m3 icanhazip.com 2>/dev/null || echo "")
    c_ip=$(get_client_addr)
    uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' "$SB_CONF" 2>/dev/null)
    pk=$(jq -r '.inbounds[0].tls.reality.public_key // empty' "$SB_CONF" 2>/dev/null)
    sid=$(jq -r '.inbounds[0].tls.reality.short_id[0] // empty' "$SB_CONF" 2>/dev/null)
    ports=$(jq -r '[.inbounds[] | select(.type=="vless") | .listen_port] | join(",")' "$SB_CONF" 2>/dev/null)
    p1=$(echo "$ports" | cut -d',' -f1)
    c_p1=$(get_client_port "$p1")
    if [[ -n "$uuid" && -n "$pk" && -n "$sid" && -n "$c_ip" && -n "$p1" ]]; then
        vless="vless://${uuid}@${c_ip}:${c_p1}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=${pk}&sid=${sid}&type=tcp#%E5%A4%A7%E9%94%A4-%E5%87%BA%E5%8F%A3-1"
        clash_yaml="proxies:\n  - name: 大锤-出口-1\n    type: vless\n    server: ${c_ip}\n    port: ${c_p1}\n    uuid: ${uuid}\n    network: tcp\n    tls: true\n    flow: xtls-rprx-vision\n    servername: apple.com\n    reality-opts:\n      public-key: ${pk}\n      short-id: ${sid}\n    client-fingerprint: chrome\n"
        sub_links=$(jq -n --arg vless "$vless" --arg clash "$clash_yaml" --arg b64 "$(echo -n "$vless" | base64)" \
            '[{name:"Vless-Reality",url:$vless},{name:"Clash-Meta",url:$clash},{name:"Base64",url:$b64}]')
    fi
fi

# ---- Gist 配置状态 ----
gist_configured=0
if [[ -f "/etc/hammer-sb/gist_token.conf" ]]; then
    gist_token=$(head -1 /etc/hammer-sb/gist_token.conf)
    gist_id=$(tail -1 /etc/hammer-sb/gist_token.conf)
    [[ -n "$gist_token" && -n "$gist_id" ]] && gist_configured=1
fi

# ---- 组装最终 state.json ----
jq -n \
    --argjson traffic "{\"used_gb\":\"$used_gb\",\"total_gb\":\"$TOTAL_GB\",\"remain_gb\":\"$remain_gb\",\"pct\":\"$pct\",\"down_bytes\":$total_down,\"up_bytes\":$total_up,\"down_speed\":\"$down_speed\",\"up_speed\":\"$up_speed\",\"reset_day\":\"$RESET_DAY\"}" \
    --argjson vps "{\"ip\":\"${v4:-N/A}\",\"region\":\"${region:-Unknown}\",\"os\":\"${release:-N/A}\",\"arch\":\"${arch:-N/A}\",\"virt\":\"${virt:-N/A}\",\"bbr\":\"${bbr_status:-N/A}\",\"sb_ver\":\"${local_sb_ver:-N/A}\",\"sb_running\":\"$(systemctl is-active hammer-sb 2>/dev/null || echo stopped)\"}" \
    --argjson nodes "$warp_nodes" \
    --argjson protocols "{\"vl\":$vl,\"vm\":$vm,\"hy\":$hy,\"tc\":$tc,\"an\":$an}" \
    --argjson subs "$sub_links" \
    --argjson _gist "{\"configured\":$gist_configured}" \
    '{$traffic, $vps, $nodes, $protocols, $subs, $_gist}' \
    > "$STATE_FILE"