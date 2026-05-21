#!/bin/bash

# [大锤sand-box] 订阅管理模块 (GitLab Git Push 方案)
# 对标 yg 脚本: 用 git push 推送订阅文件到 GitLab 项目
# 支持 Clash/Sing-Box/Base64 三合一

source ./core.sh

SB_CONFIG_DIR="/etc/hammer-sb"
SB_CONF="$SB_CONFIG_DIR/config.json"
GITLAB_CONF="$SB_CONFIG_DIR/gitlab.conf"

# 获取动态运行参数
extract_params() {
    uuid=$(jq -r '.inbounds[] | select(.type=="vless") | .users[0].uuid' "$SB_CONF" 2>/dev/null || echo "")
    p_vl=$(jq -r '.inbounds[] | select(.tag=="in-vl") | .listen_port' "$SB_CONF" 2>/dev/null || echo "")
    p_vm=$(jq -r '.inbounds[] | select(.tag=="in-vm") | .listen_port' "$SB_CONF" 2>/dev/null || echo "")
    p_hy=$(jq -r '.inbounds[] | select(.tag=="in-hy") | .listen_port' "$SB_CONF" 2>/dev/null || echo "")
    p_tc=$(jq -r '.inbounds[] | select(.tag=="in-tc") | .listen_port' "$SB_CONF" 2>/dev/null || echo "")
    p_an=$(jq -r '.inbounds[] | select(.tag=="in-an") | .listen_port' "$SB_CONF" 2>/dev/null || echo "")
    pbk=$(cat "$SB_CONFIG_DIR/reality_pub.key" 2>/dev/null || jq -r '.inbounds[] | select(.type=="vless") | .tls.reality.public_key // empty' "$SB_CONF" 2>/dev/null || echo "")
    if [[ -z "$pbk" ]]; then
        # 从 private_key 推导 public_key
        local priv=$(jq -r '.inbounds[] | select(.tag=="in-vl") | .tls.reality.private_key' "$SB_CONF" 2>/dev/null)
        if [[ -n "$priv" ]]; then
            pbk=$($SB_BINARY_PATH generate reality-keypair 2>/dev/null | jq -r '.public_key // empty' 2>/dev/null || echo "")
        fi
    fi
    sid=$(cat "$SB_CONFIG_DIR/reality_sid.key" 2>/dev/null || jq -r '.inbounds[] | select(.tag=="in-vl") | .tls.reality.short_id[0] // empty' "$SB_CONF" 2>/dev/null || echo "ab12cd34")
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

# 4. 设置 GitLab 订阅 (对标 yg 的 gitlabsub)
setup_gitlab() {
    echo -e "${blue}======================================${plain}"
    echo -e "${green}   GitLab 订阅链接设置     ${plain}"
    echo -e "${blue}======================================${plain}"
    echo -e "请确保 GitLab 官网上已建立项目，已获取访问令牌"
    echo -e "${yellow}多台 VPS 可共用一个令牌及项目名，通过不同分支区分${plain}"

    # 读取已有配置
    local old_email="" old_token="" old_userid="" old_project="" old_branch=""
    if [[ -f "$GITLAB_CONF" ]]; then
        old_email=$(grep '^EMAIL=' "$GITLAB_CONF" | cut -d= -f2-)
        old_token=$(grep '^TOKEN=' "$GITLAB_CONF" | cut -d= -f2-)
        old_userid=$(grep '^USERID=' "$GITLAB_CONF" | cut -d= -f2-)
        old_project=$(grep '^PROJECT=' "$GITLAB_CONF" | cut -d= -f2-)
        old_branch=$(grep '^BRANCH=' "$GITLAB_CONF" | cut -d= -f2-)
        echo -e "当前配置: 用户=${yellow}${old_userid}${plain} 项目=${yellow}${old_project}${plain} 分支=${yellow}${old_branch:-main}${plain}"
    fi

    echo -e "${blue}--------------------------------------${plain}"
    echo -e "1: 设置/重置 GitLab 订阅链接"
    echo -e "0: 返回"
    read -p "请选择 [0-1]: " gl_choice
    [[ "$gl_choice" != "1" ]] && return

    read -p "输入登录邮箱: " email
    read -p "输入访问令牌: " token
    read -p "输入用户名: " userid
    read -p "输入项目名: " project
    echo ""
    echo -e "${green}多台VPS共用一个令牌及项目名，可创建多个分支订阅链接${plain}"
    echo -e "${green}回车跳过表示不新建，仅使用主分支main订阅链接(首台VPS建议回车跳过)${plain}"
    read -p "新建分支名称: " gitlabml

    local git_sk="main"
    local gitlab_ml=""
    if [[ -n "$gitlabml" ]]; then
        gitlab_ml=":${gitlabml}"
        git_sk="${gitlabml}"
    fi

    # 保存配置
    cat > "$GITLAB_CONF" <<EOF
EMAIL=$email
TOKEN=$token
USERID=$userid
PROJECT=$project
BRANCH=$git_sk
EOF
    chmod 600 "$GITLAB_CONF"

    # 初始化 git 仓库
    cd "$SB_CONFIG_DIR"
    rm -rf .git
    git init >/dev/null 2>&1
    git add hammer_singbox_client.json hammer_clash.yaml hammer_base64.txt >/dev/null 2>&1
    git config user.email "$email" >/dev/null 2>&1
    git config user.name "$userid" >/dev/null 2>&1
    git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1

    # 重命名 master → main
    local branches=$(git branch)
    if [[ "$branches" == *master* ]]; then
        git branch -m master main >/dev/null 2>&1
    fi

    # 设置 remote
    git remote add origin "https://${userid}:${token}@gitlab.com/${userid}/${project}.git" >/dev/null 2>&1

    # 首次推送 (用 GIT_TERMINAL_PROMPT=0 防止交互，token 已在 URL 中)
    if [[ -d "$SB_CONFIG_DIR/.git" ]]; then
        GIT_TERMINAL_PROMPT=0 git push -f origin "main${gitlab_ml}" 2>&1 || {
            # 如果直接 push 失败，尝试 expect 方式
            if command -v expect &>/dev/null; then
                cat > "$SB_CONFIG_DIR/gitpush.sh" <<PUSHEOF
#!/usr/bin/expect
spawn bash -c "git push -f origin main${gitlab_ml}"
expect "Password for*"
send "${token}\r"
expect eof
PUSHEOF
                chmod +x "$SB_CONFIG_DIR/gitpush.sh"
                bash "$SB_CONFIG_DIR/gitpush.sh" >/dev/null 2>&1
            else
                log_error "git push 失败，请检查 Token 和项目名是否正确。"
                log_error "提示: 安装 expect 可能有助于解决密码交互问题 (apt install expect)"
            fi
        }

        # 生成订阅链接 (对标 yg 格式: GitLab API raw file URL)
        local encoded_project=$(echo -n "${userid}/${project}" | jq -sRr @uri)
        echo "https://gitlab.com/api/v4/projects/${encoded_project}/repository/files/hammer_singbox_client.json/raw?ref=${git_sk}&private_token=${token}" > "$SB_CONFIG_DIR/sing_box_gitlab.txt"
        echo "https://gitlab.com/api/v4/projects/${encoded_project}/repository/files/hammer_clash.yaml/raw?ref=${git_sk}&private_token=${token}" > "$SB_CONFIG_DIR/clash_meta_gitlab.txt"
        echo "https://gitlab.com/api/v4/projects/${encoded_project}/repository/files/hammer_base64.txt/raw?ref=${git_sk}&private_token=${token}" > "$SB_CONFIG_DIR/base64_gitlab.txt"

        show_sub_links
    else
        log_error "GitLab 订阅设置失败，请检查配置。"
    fi
    cd - >/dev/null
}

# 显示订阅链接
show_sub_links() {
    local sb_link=$(cat "$SB_CONFIG_DIR/sing_box_gitlab.txt" 2>/dev/null)
    local clash_link=$(cat "$SB_CONFIG_DIR/clash_meta_gitlab.txt" 2>/dev/null)
    local b64_link=$(cat "$SB_CONFIG_DIR/base64_gitlab.txt" 2>/dev/null)

    echo -e "${blue}======================================${plain}"
    echo -e "${green}   三合一订阅已推送至 GitLab    ${plain}"
    echo -e "${blue}======================================${plain}"
    [[ -n "$sb_link" ]] && echo -e "SB 订阅:    ${yellow}${sb_link}${plain}"
    [[ -n "$clash_link" ]] && echo -e "Clash 订阅: ${yellow}${clash_link}${plain}"
    [[ -n "$b64_link" ]] && echo -e "Base64 订阅: ${yellow}${b64_link}${plain}"
    echo -e "${blue}======================================${plain}"
}

# 5. 推送订阅到 GitLab (对标 yg 的 gitlabsubgo)
sync_to_gitlab() {
    extract_params

    if [[ -z "$uuid" || -z "$ip" ]]; then
        log_error "无法提取配置参数，请先执行初始化。"
        return 1
    fi

    gen_clash
    gen_singbox_client
    gen_base64_sub

    # 检查是否已配置 GitLab
    if [[ ! -f "$GITLAB_CONF" ]]; then
        log_warn "未配置 GitLab 订阅，订阅文件已生成到本地。"
        echo -e "${yellow}是否现在设置 GitLab 订阅推送？(y/N): ${plain}"
        read -p "" cfg
        if [[ "$cfg" == "y" || "$cfg" == "Y" ]]; then
            setup_gitlab
            return
        fi
        print_local_paths
        return
    fi

    # 读取 GitLab 配置
    source "$GITLAB_CONF"
    local gitlab_ml=""
    [[ -n "${BRANCH:-}" && "${BRANCH:-}" != "main" ]] && gitlab_ml=":${BRANCH}"

    log_info "正在推送订阅到 GitLab..."

    cd "$SB_CONFIG_DIR"

    if [[ ! -d ".git" ]]; then
        # git 仓库不存在，重新初始化
        git init >/dev/null 2>&1
        git config user.email "${EMAIL}" >/dev/null 2>&1
        git config user.name "${USERID}" >/dev/null 2>&1
        git remote add origin "https://${USERID}:${TOKEN}@gitlab.com/${USERID}/${PROJECT}.git" >/dev/null 2>&1
    else
        # 确保 remote URL 包含 token
        git remote set-url origin "https://${USERID}:${TOKEN}@gitlab.com/${USERID}/${PROJECT}.git" >/dev/null 2>&1
    fi

    # 更新文件并推送 (对标 yg: git rm → git add → commit → push)
    # 先 touch 确保文件时间戳更新，让 git 检测到变化
    touch hammer_singbox_client.json hammer_clash.yaml hammer_base64.txt
    git rm --cached hammer_singbox_client.json hammer_clash.yaml hammer_base64.txt >/dev/null 2>&1
    git add hammer_singbox_client.json hammer_clash.yaml hammer_base64.txt >/dev/null 2>&1
    # 如果没有变化也强制 commit (用 --allow-empty)
    git diff --cached --quiet && git commit --allow-empty -m "commit_refresh_$(date +"%F %T")" >/dev/null 2>&1 || git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1

    # 推送 (token 在 URL 中，GIT_TERMINAL_PROMPT=0 防止交互)
    local push_branch="${BRANCH:-main}"
    log_info "正在推送分支 ${push_branch}..."
    GIT_TERMINAL_PROMPT=0 git push -f origin "main:${push_branch}" 2>&1 || {
        if command -v expect &>/dev/null; then
            bash "$SB_CONFIG_DIR/gitpush.sh" >/dev/null 2>&1
        else
            log_error "推送失败，请检查 Token 和网络。"
        fi
    }

    # 更新订阅链接
    local encoded_project=$(echo -n "${USERID}/${PROJECT}" | jq -sRr @uri)
    local git_sk="${BRANCH:-main}"
    echo "https://gitlab.com/api/v4/projects/${encoded_project}/repository/files/hammer_singbox_client.json/raw?ref=${git_sk}&private_token=${TOKEN}" > "$SB_CONFIG_DIR/sing_box_gitlab.txt"
    echo "https://gitlab.com/api/v4/projects/${encoded_project}/repository/files/hammer_clash.yaml/raw?ref=${git_sk}&private_token=${TOKEN}" > "$SB_CONFIG_DIR/clash_meta_gitlab.txt"
    echo "https://gitlab.com/api/v4/projects/${encoded_project}/repository/files/hammer_base64.txt/raw?ref=${git_sk}&private_token=${TOKEN}" > "$SB_CONFIG_DIR/base64_gitlab.txt"

    show_sub_links
    cd - >/dev/null
}

print_local_paths() {
    echo -e "${blue}======================================${plain}"
    echo -e "订阅文件已保存至本地:"
    echo -e "  Clash:  ${yellow}$SB_CONFIG_DIR/hammer_clash.yaml${plain}"
    echo -e "  SB:     ${yellow}$SB_CONFIG_DIR/hammer_singbox_client.json${plain}"
    echo -e "  Base64: ${yellow}$SB_CONFIG_DIR/hammer_base64.txt${plain}"
    echo -e "${blue}======================================${plain}"
}
