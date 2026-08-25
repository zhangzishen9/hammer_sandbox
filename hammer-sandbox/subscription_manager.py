#!/usr/bin/env python3
"""Shared-port subscription credentials, V2Ray API accounting and HTTP serving."""
import copy, json, os, secrets, subprocess, sys, threading, time, urllib.request, uuid
from datetime import datetime, timedelta
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

ROOT = "/etc/hammer-sb"
DB = f"{ROOT}/subscriptions.json"
CONFIG = f"{ROOT}/config.json"
PUBLIC_KEY = f"{ROOT}/reality_pub.key"
STATS = "/usr/local/bin/hammer-stats"
LOCK = threading.RLock()
PROTO = {"vl": "vless", "vm": "vmess", "hy": "hysteria2", "tc": "tuic", "an": "anytls"}
SOURCE_TAG = {p: f"in-{p}" for p in PROTO}

def load_db():
    try:
        with open(DB, encoding="utf-8") as f: return json.load(f)
    except (OSError, ValueError): return []

def save_db(items):
    tmp = DB + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f: json.dump(items, f, ensure_ascii=False, indent=2)
    os.chmod(tmp, 0o600); os.replace(tmp, DB)

def user_name(item): return "hs_" + item["token"][:12]

def migrate(items):
    changed = False
    default_server = None
    if any("server" not in item for item in items):
        try: default_server = urllib.request.urlopen("https://api.ipify.org", timeout=3).read().decode().strip()
        except Exception: default_server = "127.0.0.1"
    for item in items:
        if "credential" not in item: item["credential"] = str(uuid.uuid4()); changed = True
        if "short_id" not in item: item["short_id"] = secrets.token_hex(8); changed = True
        if "server" not in item: item["server"] = default_server; changed = True
        if "upload_bytes" not in item:
            item["upload_bytes"] = 0; changed = True
        if "download_bytes" not in item:
            item["download_bytes"] = int(item.get("used_bytes", 0)); changed = True
        item["used_bytes"] = int(item["upload_bytes"]) + int(item["download_bytes"])
        item.setdefault("reset_day", 1)
    return changed

def billing_cycle(reset_day):
    now = datetime.now()
    anchor = now.replace(day=reset_day, hour=0, minute=0, second=0, microsecond=0)
    if now < anchor:
        previous = anchor.replace(day=1) - timedelta(days=1)
        anchor = previous.replace(day=reset_day)
    return anchor.strftime("%Y-%m-%d")

def collect_stats(items):
    """Fetch and reset sing-box counters. Failure leaves persisted totals untouched."""
    if not os.path.isfile(STATS): return False
    try:
        raw = subprocess.check_output([STATS, "127.0.0.1:8080"], timeout=5, stderr=subprocess.DEVNULL)
        stats = json.loads(raw)
    except Exception:
        return False
    by_user = {user_name(item): item for item in items}
    for name, value in stats.items():
        parts = name.split(">>>")
        if len(parts) != 4 or parts[0] != "user" or parts[2] != "traffic": continue
        item = by_user.get(parts[1])
        if not item: continue
        field = "upload_bytes" if parts[3] == "uplink" else "download_bytes" if parts[3] == "downlink" else None
        if field: item[field] = int(item.get(field, 0)) + max(0, int(value))
    for item in items: item["used_bytes"] = int(item.get("upload_bytes", 0)) + int(item.get("download_bytes", 0))
    return True

def apply_cycles(items):
    changed = False
    for item in items:
        cycle = billing_cycle(int(item.get("reset_day", 1)))
        if item.get("billing_cycle") != cycle:
            item["billing_cycle"] = cycle
            item["upload_bytes"] = item["download_bytes"] = item["used_bytes"] = 0
            changed = True
    return changed

def is_active(item):
    now = int(time.time())
    return bool(item.get("enabled")) and not (item.get("expire", 0) and now > item["expire"]) and int(item.get("used_bytes", 0)) < int(item["total_bytes"])

def subscription_user(p, item):
    name, cred = user_name(item), item["credential"]
    if p == "vl": return {"name": name, "uuid": cred, "flow": "xtls-rprx-vision"}
    if p == "vm": return {"name": name, "uuid": cred, "alterId": 0}
    if p == "hy": return {"name": name, "password": cred}
    if p == "tc": return {"name": name, "uuid": cred, "password": cred}
    return {"name": name, "password": cred}

def reconcile(collect=True):
    with LOCK:
        items = load_db(); migrate(items)
        if collect: collect_stats(items)
        apply_cycles(items)
        for item in items: item["active_runtime"] = is_active(item)
        with open(CONFIG, encoding="utf-8") as f: config = json.load(f)
        original = copy.deepcopy(config)

        # Migrate old random-port inbounds and users, preserving the administrator account.
        config["inbounds"] = [x for x in config.get("inbounds", []) if not x.get("tag", "").startswith("sub-")]
        config.setdefault("route", {}).setdefault("rules", [])
        config["route"]["rules"] = [x for x in config["route"]["rules"] if not any(str(t).startswith("sub-") for t in (x.get("inbound") or []))]
        templates = {p: next((x for x in config["inbounds"] if x.get("tag") == SOURCE_TAG[p]), None) for p in PROTO}
        for inbound in templates.values():
            if inbound: inbound["users"] = [u for u in inbound.get("users", []) if not str(u.get("name", "")).startswith("hs_")]

        active_users = []
        for item in items:
            if not item["active_runtime"]: continue
            active_users.append(user_name(item))
            for p in item.get("protocols", []):
                if templates.get(p): templates[p].setdefault("users", []).append(subscription_user(p, item))
            if templates.get("vl") and "vl" in item.get("protocols", []):
                ids = templates["vl"].setdefault("tls", {}).setdefault("reality", {}).setdefault("short_id", [])
                if item["short_id"] not in ids: ids.append(item["short_id"])

        if templates.get("vl"):
            try: admin_sid = open(f"{ROOT}/reality_sid.key").read().strip()
            except OSError: admin_sid = ""
            active_sids = [x["short_id"] for x in items if x.get("active_runtime") and "vl" in x.get("protocols", [])]
            templates["vl"]["tls"]["reality"]["short_id"] = ([admin_sid] if admin_sid else []) + active_sids

        experimental = config.setdefault("experimental", {})
        experimental["v2ray_api"] = {"listen": "127.0.0.1:8080", "stats": {"enabled": True, "users": active_users}}
        if config != original:
            tmp = CONFIG + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f: json.dump(config, f, ensure_ascii=False, indent=2)
            subprocess.run(["/usr/local/bin/sing-box", "check", "-c", tmp], check=True)
            os.replace(tmp, CONFIG)
        save_db(items)
        if config != original: subprocess.run(["systemctl", "reload", "hammer-sb"], check=True)

def yaml_for(item):
    addr, cred = item["server"], item["credential"]
    config = json.load(open(CONFIG, encoding="utf-8"))
    inbounds = {x.get("tag"): x for x in config.get("inbounds", [])}
    ports = {p: inbounds[SOURCE_TAG[p]]["listen_port"] for p in item["protocols"] if SOURCE_TAG[p] in inbounds}
    vl = inbounds.get("in-vl", {}); vm = inbounds.get("in-vm", {})
    reality_sni = vl.get("tls", {}).get("server_name", "apple.com")
    vm_path = vm.get("transport", {}).get("path", "/hammer-vm")
    try: pub = open(PUBLIC_KEY).read().strip()
    except OSError: pub = ""
    blocks, names = [], []
    for p in item["protocols"]:
        if p not in ports: continue
        port, name = ports[p], f'{item["name"]}-{p.upper()}'; names.append(name)
        common = f"  - name: {name}\n    server: {addr}\n    port: {port}\n"
        if p == "vl": block = common + f"    type: vless\n    uuid: {cred}\n    network: tcp\n    udp: true\n    tls: true\n    flow: xtls-rprx-vision\n    servername: {reality_sni}\n    reality-opts:\n      public-key: {pub}\n      short-id: {item['short_id']}\n    client-fingerprint: chrome\n"
        elif p == "vm": block = common + f"    type: vmess\n    uuid: {cred}\n    alterId: 0\n    cipher: auto\n    network: ws\n    ws-opts:\n      path: {vm_path}\n"
        elif p == "hy": block = common + f"    type: hysteria2\n    password: {cred}\n    sni: www.bing.com\n    skip-cert-verify: true\n"
        elif p == "tc": block = common + f"    type: tuic\n    uuid: {cred}\n    password: {cred}\n    sni: www.bing.com\n    skip-cert-verify: true\n"
        else: block = common + f"    type: anytls\n    password: {cred}\n    sni: www.bing.com\n    skip-cert-verify: true\n"
        blocks.append(block)
    entries = "".join(f"      - {n}\n" for n in names)
    return ("port: 7890\nallow-lan: true\nmode: rule\nlog-level: info\nproxies:\n" + "".join(blocks) +
            "proxy-groups:\n  - name: 自动选择\n    type: url-test\n    url: https://www.gstatic.com/generate_204\n    interval: 300\n    proxies:\n" + entries +
            "  - name: 选择代理节点\n    type: select\n    proxies:\n      - 自动选择\n      - DIRECT\n" + entries +
            "rules:\n  - GEOIP,LAN,DIRECT\n  - GEOIP,CN,DIRECT\n  - MATCH,选择代理节点\n")

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        token = self.path.split("?", 1)[0].replace("/sub/", "", 1).strip("/")
        with LOCK:
            items = load_db(); item = next((x for x in items if x.get("token") == token), None)
        if not item or not is_active(item): self.send_error(404); return
        body = yaml_for(item).encode(); upload = int(item.get("upload_bytes", 0)); download = int(item.get("download_bytes", 0))
        self.send_response(200); self.send_header("Content-Type", "text/yaml; charset=utf-8")
        self.send_header("Subscription-Userinfo", f'upload={upload}; download={download}; total={item["total_bytes"]}; expire={item.get("expire",0)}')
        self.send_header("Profile-Update-Interval", "6"); self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *_): pass

def monitor():
    while True:
        try: reconcile()
        except Exception: pass
        time.sleep(30)

if __name__ == "__main__":
    if len(sys.argv) < 2: raise SystemExit("usage: subscription_manager.py reconcile|serve [port]")
    if sys.argv[1] == "reconcile": reconcile()
    elif sys.argv[1] == "settle":
        with LOCK:
            records = load_db(); migrate(records); collect_stats(records); save_db(records)
    elif sys.argv[1] == "serve":
        threading.Thread(target=monitor, daemon=True).start()
        ThreadingHTTPServer(("0.0.0.0", int(sys.argv[2])), Handler).serve_forever()
