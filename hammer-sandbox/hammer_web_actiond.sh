#!/bin/bash
# [大锤sand-box] Web UI 统一服务 (静态文件 + API)
# 基于 python3，同时提供 HTML 和 API，解决 CORS 问题
# 启动: bash hammer_web_actiond.sh start

PID_FILE="/tmp/hammer-actiond.pid"
PORT=15000
PASS_FILE="/etc/hammer-sb/ui_pass.conf"
UI_DIR="/etc/hammer-sb/ui"

start_daemon() {
    if [[ -f "$PID_FILE" ]] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "actiond 已在运行 (pid $(cat $PID_FILE))"
        return
    fi

    # 确保目录和文件存在
    mkdir -p "$UI_DIR/api"
    bash /etc/hammer-sb/ui/hammer_web_state.sh >/dev/null 2>&1

    python3 -c "
import json, os, subprocess, urllib.parse, hashlib, time, base64, mimetypes
from http.server import HTTPServer, BaseHTTPRequestHandler

SB_CONF_DIR = '/etc/hammer-sb'
SCRIPT_DIR = '/root/hammer-sandbox'
PASS_FILE = '$PASS_FILE'
UI_DIR = '$UI_DIR'

def make_token(pw):
    h = hashlib.sha256(f'{pw}:hammer2024:{time.strftime(\"%Y%m%d%H\")}'.encode()).hexdigest()[:16]
    return h

def check_token(tok):
    try:
        with open(PASS_FILE) as f:
            pw = f.read().strip()
    except:
        return True
    if not pw:
        return True
    return tok == make_token(pw)

class Handler(BaseHTTPRequestHandler):
    def reply(self, ok, **extra):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        resp = {'ok': ok}
        resp.update(extra)
        self.wfile.write(json.dumps(resp, ensure_ascii=False).encode())

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()

    def do_POST(self):
        self.do_GET()

    def do_GET(self):
        p = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(p.query)

        # API 路由
        if p.path in ('/login', '/check_auth', '/action'):
            self.handle_api(p, q)
            return

        # 静态文件服务
        self.serve_static(p.path)

    def handle_api(self, p, q):
        if p.path == '/login':
            pw_in = q.get('pass', [''])[0]
            try:
                with open(PASS_FILE) as f:
                    real_pw = f.read().strip()
            except:
                real_pw = ''
            if not real_pw or pw_in == real_pw:
                tk = make_token(real_pw) if real_pw else ''
                self.reply(True, token=tk)
            else:
                self.reply(False, error='密码错误')
            return

        if p.path == '/check_auth':
            tok = q.get('token', [''])[0]
            self.reply(check_token(tok))
            return

        # /action 需要验证
        tok = q.get('token', [''])[0]
        if not check_token(tok):
            self.reply(False, error='auth required')
            return

        a = q.get('type', [''])[0]
        if a == 'proto':
            k = q.get('key', [''])[0].upper()
            v = q.get('val', ['0'])[0]
            if k and v in ('0', '1'):
                os.system(f\"sed -i 's/^{k}=[01]/{k}={v}/' {SB_CONF_DIR}/protocols.conf\")
                os.system(f'systemctl reload hammer-sb &')
                self.reply(True, action='proto', key=k, val=int(v))
            else:
                self.reply(False, error='invalid params')
        elif a == 'rotate':
            subprocess.Popen(['bash', f'{SCRIPT_DIR}/warp_rotate.sh'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.reply(True, action='rotate')
        elif a == 'bbr':
            v = q.get('val', ['1'])[0]
            if v == '1':
                os.system('modprobe tcp_bbr 2>/dev/null')
                os.system(\"grep -q 'net.core.default_qdisc=fq' /etc/sysctl.conf || echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf\")
                os.system(\"grep -q 'net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf || echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf\")
                os.system('sysctl -p >/dev/null 2>&1')
            self.reply(True, action='bbr', val=int(v))
        elif a == 'quota':
            tg = q.get('total', [''])[0]
            rd = q.get('reset_day', [''])[0]
            if tg and rd:
                with open(f'{SB_CONF_DIR}/quota.conf', 'w') as f:
                    f.write(f'TOTAL_GB={tg}\\nRESET_DAY={rd}\\n')
                self.reply(True, action='quota', total=int(tg), reset_day=int(rd))
            else:
                self.reply(False, error='invalid params')
        elif a == 'reset_traffic':
            os.system(f'rm -f {SB_CONF_DIR}/usage.db')
            self.reply(True, action='reset_traffic')
        elif a == 'set_pass':
            new_pass = q.get('val', [''])[0]
            if new_pass:
                with open(PASS_FILE, 'w') as f:
                    f.write(new_pass.strip())
                self.reply(True, action='set_pass')
            elif new_pass == '':
                if os.path.exists(PASS_FILE):
                    os.remove(PASS_FILE)
                self.reply(True, action='set_pass', cleared=True)
            else:
                self.reply(False, error='invalid params')
        elif a == 'sync_sub':
            subprocess.Popen(['bash', f'{SCRIPT_DIR}/sync_gitlab.sh'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.reply(True, action='sync_sub', msg='正在后台推送订阅...')
        else:
            self.reply(False, error=f'unknown action: {a}')

    def serve_static(self, path):
        if path == '/':
            path = '/index.html'
        # 安全: 不允许跳出 UI_DIR
        filepath = os.path.normpath(UI_DIR + path)
        if not filepath.startswith(UI_DIR):
            self.send_error(403)
            return
        if not os.path.isfile(filepath):
            self.send_error(404)
            return
        mt, _ = mimetypes.guess_type(filepath)
        if not mt:
            mt = 'application/octet-stream'
        self.send_response(200)
        self.send_header('Content-Type', mt)
        self.send_header('Cache-Control', 'no-cache')
        with open(filepath, 'rb') as f:
            data = f.read()
        self.send_header('Content-Length', len(data))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass

s = HTTPServer(('0.0.0.0', $PORT), Handler)
with open('$PID_FILE', 'w') as f:
    f.write(str(os.getpid()))
s.serve_forever()
" &
    echo $! > "$PID_FILE"
    echo "actiond 已启动 (pid $!, port $PORT)"
}

stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null && echo "actiond 已停止 (pid $pid)"
        rm -f "$PID_FILE"
    else
        echo "actiond 未运行"
    fi
}

case "${1:-start}" in
    start) start_daemon ;;
    stop)  stop_daemon ;;
    restart) stop_daemon; sleep 0.5; start_daemon ;;
    *) echo "用法: $0 {start|stop|restart}" ;;
esac
