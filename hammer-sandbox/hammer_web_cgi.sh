#!/bin/bash
# [大锤sand-box] Web UI CGI 动作处理器
# 由 busybox httpd 调用，处理协议切换、WARP旋转等操作

echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
echo "Access-Control-Allow-Headers: Content-Type, Authorization"
echo ""

read -r QUERY_STRING
# busybox httpd passes query string via QUERY_STRING env var or stdin
# 解析 action 参数
action=$(echo "$QUERY_STRING" | sed 's/.*action=\([^&]*\).*/\1/')

case "$action" in
    proto)
        key=$(echo "$QUERY_STRING" | sed 's/.*key=\([^&]*\).*/\1/')
        val=$(echo "$QUERY_STRING" | sed 's/.*val=\([^&]*\).*/\1/')
        pf="/etc/hammer-sb/protocols.conf"
        if [[ -f "$pf" && -n "$key" && -n "$val" ]]; then
            sed -i "s/^${key^^}=[01]/${key^^}=$val/" "$pf"
            # 触发重载
            bash /etc/hammer-sb/ui/hammer_web_state.sh >/dev/null 2>&1 &
            echo '{"ok":true}'
        else
            echo '{"ok":false,"error":"invalid params"}'
        fi
        ;;
    rotate)
        SCRIPT_DIR="/root/hammer-sandbox"
        if [[ -d "$SCRIPT_DIR" ]]; then
            cd "$SCRIPT_DIR" && bash ./warp_rotate.sh >/dev/null 2>&1 &
            echo '{"ok":true}'
        else
            echo '{"ok":false,"error":"script dir not found"}'
        fi
        ;;
    bbr)
        val=$(echo "$QUERY_STRING" | sed 's/.*val=\([^&]*\).*/\1/')
        if [[ "$val" == "1" ]]; then
            modprobe tcp_bbr 2>/dev/null
            grep -q "^net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
            grep -q "^net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            sysctl -p >/dev/null 2>&1
        fi
        echo '{"ok":true}'
        ;;
    quota)
        tg=$(echo "$QUERY_STRING" | sed 's/.*total=\([^&]*\).*/\1/')
        rd=$(echo "$QUERY_STRING" | sed 's/.*reset_day=\([^&]*\).*/\1/')
        if [[ -n "$tg" && -n "$rd" ]]; then
            cat > /etc/hammer-sb/quota.conf <<EOF
TOTAL_GB=$tg
RESET_DAY=$rd
EOF
            echo '{"ok":true}'
        else
            echo '{"ok":false,"error":"invalid params"}'
        fi
        ;;
    reset_traffic)
        rm -f /etc/hammer-sb/usage.db
        echo '{"ok":true}'
        ;;
    *)
        echo '{"ok":false,"error":"unknown action"}'
        ;;
esac