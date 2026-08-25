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
    read -p "到期日期 YYYY-MM-DD (留空永久): " sub_expire_date
    local sub_expire=0
    if [[ -n "$sub_expire_date" ]]; then
        sub_expire=$(date -d "$sub_expire_date 23:59:59" +%s 2>/dev/null) || { log_error "日期格式无效。"; return 1; }
    fi
    local token=$(openssl rand -hex 24)
    local protocols_json=$(printf '%s' "$sub_protocols" | tr ',' '\n' | jq -R . | jq -s .)
    local total_bytes=$((sub_total * 1073741824))
    jq --arg token "$token" --arg name "$sub_name" --argjson protocols "$protocols_json" \
       --argjson total "$total_bytes" --argjson expire "$sub_expire" \
       '. += [{token:$token,name:$name,protocols:$protocols,total_bytes:$total,expire:$expire,enabled:true}]' \
       "$SUB_DB" > "$SUB_DB.tmp" && mv "$SUB_DB.tmp" "$SUB_DB"
    chmod 600 "$SUB_DB"
    local addr=$(get_client_addr)
    log_info "订阅地址: http://${addr}:${SUB_PORT}/sub/${token}"
    log_warn "这是 HTTP 链接，订阅内容和 Token 在传输途中不加密；请只发给可信用户。"
    if ! systemctl is-active --quiet hammer-sub 2>/dev/null; then
        log_info "正在自动安装并启动订阅服务..."
        install_subscription_service || {
            log_error "订阅已创建，但服务启动失败，请检查 systemctl status hammer-sub。"
            return 1
        }
    fi
}

list_subscriptions() {
    init_subscriptions
    jq -r '.[] | "名称=\(.name)  协议=\(.protocols|join(","))  配额=\(.total_bytes/1073741824|floor)GB  到期=\(if .expire==0 then "永久" else (.expire|todate) end)  状态=\(if .enabled then "启用" else "停用" end)\n链接Token=\(.token)"' "$SUB_DB"
}

revoke_subscription() {
    init_subscriptions
    read -p "输入要停用的 Token: " token
    jq --arg token "$token" 'map(if .token==$token then .enabled=false else . end)' "$SUB_DB" > "$SUB_DB.tmp" && mv "$SUB_DB.tmp" "$SUB_DB"
    chmod 600 "$SUB_DB"
    log_info "订阅已停用。"
}

install_subscription_service() {
    init_subscriptions
    cp "${SCRIPT_DIR:-$(pwd)}/subscription_server.sh" /etc/hammer-sb/subscription_server.sh
    chmod 700 /etc/hammer-sb/subscription_server.sh
    cat > /etc/systemd/system/hammer-sub.service <<EOF
[Unit]
Description=Hammer read-only subscription service
After=network.target hammer-sb.service

[Service]
User=root
ExecStart=/bin/bash /etc/hammer-sb/subscription_server.sh serve
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
    systemctl daemon-reload
    systemctl enable --now hammer-sub
    log_info "只读订阅服务已启动: ${SUB_BIND}:${SUB_PORT}。"
}

manage_subscriptions() {
    while true; do
        echo -e "${blue}================ 独立订阅管理 ================${plain}"
        echo "1. 创建订阅（协议组合/配额/到期时间）"
        echo "2. 查看订阅"
        echo "3. 停用订阅刷新（不撤销已导入节点）"
        echo "4. 手动重启订阅服务"
        echo "0. 返回"
        read -p "请选择: " sub_choice
        case "$sub_choice" in
            1) extract_params; gen_clash; create_subscription; read -p "按回车继续..." ;;
            2) list_subscriptions; read -p "按回车继续..." ;;
            3) revoke_subscription; read -p "按回车继续..." ;;
            4) install_subscription_service; read -p "按回车继续..." ;;
            0) return ;;
        esac
    done
}

serve_subscriptions() {
    exec python3 - "$SUB_PORT" <<'PY'
import json, os, re, sys, time, threading, urllib.request
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

PORT = int(sys.argv[1])
DB = '/etc/hammer-sb/subscriptions.json'
YAML = '/etc/hammer-sb/hammer_clash.yaml'
USAGE = '/etc/hammer-sb/usage.db'
NAMES = {'vl':'大锤-Vless','vm':'大锤-Vmess','hy':'大锤-Hysteria2','tc':'大锤-Tuic','an':'大锤-AnyTLS'}
USAGE_LOCK = threading.Lock()

def usage():
    with USAGE_LOCK:
        values = {}
        try:
            for line in open(USAGE, encoding='utf-8'):
                key, sep, value = line.strip().partition('=')
                if sep and value.isdigit(): values[key] = int(value)
        except OSError: pass
        try:
            with urllib.request.urlopen('http://127.0.0.1:9090/traffic', timeout=2) as response:
                live = json.loads(response.readline())
            api_up = int(live.get('upTotal', live.get('up', 0)))
            api_down = int(live.get('downTotal', live.get('down', 0)))
            if api_up < values.get('LAST_API_UP', 0):
                values['SESSION_OFFSET_UP'] = values.get('SESSION_OFFSET_UP', 0) + values.get('LAST_API_UP', 0)
            if api_down < values.get('LAST_API_DOWN', 0):
                values['SESSION_OFFSET_DOWN'] = values.get('SESSION_OFFSET_DOWN', 0) + values.get('LAST_API_DOWN', 0)
            values['LAST_API_UP'], values['LAST_API_DOWN'] = api_up, api_down
            with open(USAGE + '.tmp', 'w', encoding='utf-8') as f:
                for key in ('MONTH','DOWN_BYTES','UP_BYTES','SESSION_OFFSET_DOWN','SESSION_OFFSET_UP','LAST_API_DOWN','LAST_API_UP'):
                    f.write(f'{key}={values.get(key, 0)}\n')
            os.replace(USAGE + '.tmp', USAGE)
        except Exception: pass
        up = values.get('UP_BYTES', 0) + values.get('SESSION_OFFSET_UP', 0) + values.get('LAST_API_UP', 0)
        down = values.get('DOWN_BYTES', 0) + values.get('SESSION_OFFSET_DOWN', 0) + values.get('LAST_API_DOWN', 0)
        return up, down

def filtered_yaml(allowed):
    text = open(YAML, encoding='utf-8').read()
    before, rest = text.split('\nproxies:\n', 1)
    proxy_text, tail = rest.split('\nproxy-groups:\n', 1)
    _, rules = tail.split('\nrules:\n', 1)
    blocks = re.split(r'(?=^  - name: )', proxy_text, flags=re.M)
    selected = [NAMES[p] for p in allowed if p in NAMES]
    kept = [b for b in blocks if any(b.startswith('  - name: ' + name + '\n') for name in selected)]
    entries = ''.join(f'      - {name}\n' for name in selected)
    groups = ('proxy-groups:\n  - name: 自动选择\n    type: url-test\n'
              '    url: https://www.gstatic.com/generate_204\n    interval: 300\n    proxies:\n' + entries +
              '  - name: 选择代理节点\n    type: select\n    proxies:\n      - 自动选择\n      - DIRECT\n' + entries)
    return before + '\nproxies:\n' + ''.join(kept).rstrip() + '\n\n' + groups + '\nrules:\n' + rules

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split('?', 1)[0]
        token = path[len('/sub/'):] if path.startswith('/sub/') else ''
        token = token.strip('/')
        if not token or '/' in token:
            self.send_error(404); return
        try: profiles = json.load(open(DB, encoding='utf-8'))
        except Exception: self.send_error(503); return
        profile = next((p for p in profiles if p.get('token') == token), None)
        now = int(time.time())
        if not profile or not profile.get('enabled') or (profile.get('expire', 0) and now > profile['expire']):
            self.send_error(404); return
        try: body = filtered_yaml(profile.get('protocols', [])).encode()
        except Exception: self.send_error(503); return
        up, down = usage()
        self.send_response(200)
        self.send_header('Content-Type', 'text/yaml; charset=utf-8')
        self.send_header('Content-Disposition', 'attachment; filename="hammer.yaml"')
        self.send_header('Subscription-Userinfo', f'upload={up}; download={down}; total={profile["total_bytes"]}; expire={profile.get("expire",0)}')
        self.send_header('Profile-Update-Interval', '6')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def log_message(self, fmt, *args): pass

ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" && "${1:-}" == "serve" ]]; then
    serve_subscriptions
fi
