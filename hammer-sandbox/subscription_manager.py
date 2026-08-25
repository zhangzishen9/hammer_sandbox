#!/usr/bin/env python3
"""Per-subscription credentials, config reconciliation, accounting and HTTP serving."""
import copy, json, os, re, secrets, socket, subprocess, sys, threading, time, urllib.request, uuid
from datetime import datetime, timedelta
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

ROOT = "/etc/hammer-sb"
DB = f"{ROOT}/subscriptions.json"
CONFIG = f"{ROOT}/config.json"
PUBLIC_KEY = f"{ROOT}/reality_pub.key"
LOCK = threading.RLock()
PROTO = {"vl": "vless", "vm": "vmess", "hy": "hysteria2", "tc": "tuic", "an": "anytls"}
SOURCE_TAG = {p: f"in-{p}" for p in PROTO}
UDP = {"hy", "tc"}

def load_db():
    try:
        with open(DB, encoding="utf-8") as f: return json.load(f)
    except (OSError, ValueError): return []

def save_db(items):
    tmp = DB + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f: json.dump(items, f, ensure_ascii=False, indent=2)
    os.chmod(tmp, 0o600); os.replace(tmp, DB)

def migrate(items):
    used_ports = {int(v) for item in items for v in item.get("ports", {}).values()}
    def free_port():
        while True:
            port = secrets.randbelow(50000) + 10000
            if port in used_ports: continue
            with socket.socket() as s:
                try: s.bind(("0.0.0.0", port))
                except OSError: continue
            used_ports.add(port); return port
    changed = False
    default_server = None
    if any("server" not in item for item in items):
        try: default_server = urllib.request.urlopen("https://api.ipify.org", timeout=3).read().decode().strip()
        except Exception: default_server = "127.0.0.1"
    for item in items:
        if "credential" not in item: item["credential"] = str(uuid.uuid4()); changed = True
        if "short_id" not in item: item["short_id"] = secrets.token_hex(8); changed = True
        if "server" not in item: item["server"] = default_server; changed = True
        item.setdefault("ports", {})
        for p in item.get("protocols", []):
            if p not in item["ports"]: item["ports"][p] = free_port(); changed = True
        item.setdefault("used_bytes", 0); item.setdefault("counter_bytes", 0)
        item.setdefault("reset_day", 1)
    return changed

def billing_cycle(reset_day):
    now = datetime.now()
    anchor = now.replace(day=reset_day, hour=0, minute=0, second=0, microsecond=0)
    if now < anchor:
        previous = (anchor.replace(day=1) - timedelta(days=1))
        anchor = previous.replace(day=reset_day)
    return anchor.strftime("%Y-%m-%d")

def nft_counts():
    result = {}
    try:
        raw = subprocess.check_output(["nft", "-j", "list", "table", "inet", "hammer_sub"], stderr=subprocess.DEVNULL)
        for entry in json.loads(raw).get("nftables", []):
            rule = entry.get("rule", {})
            comment = rule.get("comment", "")
            match = re.fullmatch(r"hs_([0-9a-f]{12})_(in|out)", comment)
            if not match: continue
            total = sum(x.get("counter", {}).get("bytes", 0) for x in rule.get("expr", []))
            result[match.group(1)] = result.get(match.group(1), 0) + total
    except Exception: pass
    return result

def snapshot(items):
    counts = nft_counts()
    for item in items:
        short = item["token"][:12]
        current = counts.get(short, 0)
        previous = int(item.get("counter_bytes", 0))
        if current >= previous:
            item["used_bytes"] = int(item.get("used_bytes", 0)) + current - previous
        item["counter_bytes"] = current

def current_used(item, counts=None):
    counts = counts if counts is not None else nft_counts()
    current = counts.get(item["token"][:12], 0)
    previous = int(item.get("counter_bytes", 0))
    return int(item.get("used_bytes", 0)) + max(0, current - previous)

def rebuild_nft(items):
    lines = ["table inet hammer_sub {", " chain input { type filter hook input priority 0; policy accept;",
             " }", " chain output { type filter hook output priority 0; policy accept;", " }", "}"]
    rules = []
    for item in items:
        if not item.get("active_runtime"): continue
        short = item["token"][:12]
        tcp = [v for k, v in item["ports"].items() if k not in UDP]
        udp = [v for k, v in item["ports"].items() if k in UDP]
        for family, ports in (("tcp", tcp), ("udp", udp)):
            if not ports: continue
            values = ", ".join(map(str, ports))
            rules += [f'add rule inet hammer_sub input {family} dport {{ {values} }} counter comment "hs_{short}_in"',
                      f'add rule inet hammer_sub output {family} sport {{ {values} }} counter comment "hs_{short}_out"']
    subprocess.run(["nft", "delete", "table", "inet", "hammer_sub"], stderr=subprocess.DEVNULL)
    subprocess.run(["nft", "-f", "-"], input=("\n".join(lines + rules) + "\n").encode(), check=True)
    for item in items: item["counter_bytes"] = 0

def reconcile():
    with LOCK:
        items = load_db(); migrate(items); snapshot(items)
        for item in items:
            cycle = billing_cycle(int(item.get("reset_day", 1)))
            if item.get("billing_cycle") != cycle:
                item["billing_cycle"] = cycle; item["used_bytes"] = 0; item["counter_bytes"] = 0
        now = int(time.time())
        for item in items:
            item["active_runtime"] = bool(item.get("enabled")) and not (item.get("expire", 0) and now > item["expire"]) and current_used(item, {}) < item["total_bytes"]
        with open(CONFIG, encoding="utf-8") as f: config = json.load(f)
        original_config = copy.deepcopy(config)
        config["inbounds"] = [x for x in config.get("inbounds", []) if not x.get("tag", "").startswith("sub-")]
        config["route"]["rules"] = [x for x in config["route"].get("rules", []) if not any(str(t).startswith("sub-") for t in (x.get("inbound") or []))]
        templates = {p: next((x for x in config["inbounds"] if x.get("tag") == SOURCE_TAG[p]), None) for p in PROTO}
        outbound = "Warp-Pool" if any(x.get("tag") == "Warp-Pool" for x in config.get("outbounds", [])) else "direct"
        tags = []
        for item in items:
            if not item["active_runtime"]: continue
            for p in item["protocols"]:
                if not templates.get(p): continue
                node = copy.deepcopy(templates[p]); node["tag"] = f'sub-{item["token"][:12]}-{p}'; node["listen_port"] = item["ports"][p]
                cred = item["credential"]
                if p in ("vl", "vm"): node["users"] = [{"uuid": cred, **({"flow":"xtls-rprx-vision"} if p == "vl" else {"alterId":0})}]
                elif p == "hy": node["users"] = [{"password": cred}]
                elif p == "tc": node["users"] = [{"uuid": cred, "password": cred}]
                else: node["users"] = [{"name": item["token"][:12], "password": cred}]
                if p == "vl": node["tls"]["reality"]["short_id"] = [item["short_id"]]
                config["inbounds"].append(node); tags.append(node["tag"])
        if tags: config["route"]["rules"].insert(0, {"inbound": tags, "outbound": outbound})
        runtime = copy.deepcopy(config)
        if runtime != original_config:
            tmp = CONFIG + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f: json.dump(runtime, f, ensure_ascii=False, indent=2)
            subprocess.run(["/usr/local/bin/sing-box", "check", "-c", tmp], check=True)
            os.replace(tmp, CONFIG)
        rebuild_nft(items)
        save_db(items)
        if runtime != original_config:
            subprocess.run(["systemctl", "reload", "hammer-sb"], stderr=subprocess.DEVNULL)

def yaml_for(item):
    addr = item["server"]; cred = item["credential"]; ports = item["ports"]
    try:
        config = json.load(open(CONFIG, encoding="utf-8"))
        vl_template = next(x for x in config["inbounds"] if x.get("tag") == "in-vl")
        vm_template = next(x for x in config["inbounds"] if x.get("tag") == "in-vm")
        reality_sni = vl_template.get("tls", {}).get("server_name", "apple.com")
        vm_path = vm_template.get("transport", {}).get("path", "/hammer-vm")
    except Exception:
        reality_sni, vm_path = "apple.com", "/hammer-vm"
    try: pub = open(PUBLIC_KEY).read().strip()
    except OSError: pub = ""
    blocks, names = [], []
    for p in item["protocols"]:
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
            items = load_db(); counts = nft_counts(); item = next((x for x in items if x.get("token") == token), None)
            used = current_used(item, counts) if item else 0
        now = int(time.time())
        if not item or not item.get("enabled") or used >= item["total_bytes"] or (item.get("expire", 0) and now > item["expire"]): self.send_error(404); return
        body = yaml_for(item).encode()
        self.send_response(200); self.send_header("Content-Type", "text/yaml; charset=utf-8")
        self.send_header("Subscription-Userinfo", f'upload=0; download={used}; total={item["total_bytes"]}; expire={item.get("expire",0)}')
        self.send_header("Profile-Update-Interval", "6"); self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *_): pass

def monitor():
    while True:
        try: reconcile()
        except Exception: pass
        time.sleep(30)

if __name__ == "__main__":
    if sys.argv[1] == "reconcile": reconcile()
    elif sys.argv[1] == "serve":
        threading.Thread(target=monitor, daemon=True).start()
        ThreadingHTTPServer(("0.0.0.0", int(sys.argv[2])), Handler).serve_forever()
