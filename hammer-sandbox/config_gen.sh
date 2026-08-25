#!/bin/bash

# [大锤sand-box] 配置生成模块 (Final Expert Version)
# 5协议 + 域名分流，WARP 池由选项7单独管理

source ./core.sh

SB_CONFIG_DIR="/etc/hammer-sb"
BASE_CONF="$SB_CONFIG_DIR/base_config.json"
DOMAIN_CONF="$SB_CONFIG_DIR/warp_domains.conf"

# 参数初始化
uuid=$(cat /proc/sys/kernel/random/uuid)
fetch_ip() { export pub_ip=$(curl -s4m3 icanhazip.com || echo "您的IP"); }

# 生成密钥对 (复用)
gen_keys() {
    rkp=$($SB_BINARY_PATH generate reality-keypair 2>/dev/null)
    if echo "$rkp" | jq -e . >/dev/null 2>&1; then
        priv_key=$(echo "$rkp" | jq -r '.private_key // .privateKey // empty')
        pub_key=$(echo "$rkp" | jq -r '.public_key // .publicKey // empty')
    fi
    if [[ -z "$priv_key" ]]; then
        priv_key=$(echo "$rkp" | grep -i "private" | awk '{print $NF}')
    fi
    if [[ -z "$pub_key" ]]; then
        pub_key=$(echo "$rkp" | grep -i "public" | awk '{print $NF}')
    fi
    short_id=$(openssl rand -hex 8)
    # 持久化 public_key (config.json 里只有 private_key)
    echo "$pub_key" > "$SB_CONFIG_DIR/reality_pub.key"
    echo "$short_id" > "$SB_CONFIG_DIR/reality_sid.key"
}

generate_config() {
    log_info "正在启动大锤 [专家模式] 配置生成..."
    mkdir -p "$SB_CONFIG_DIR"

    gen_keys

    # 交互式端口设置 (回车随机，对标 yg)
    rm -f "$PORTS_CONF"
    echo -e "${blue}======================================${plain}"
    echo -e "${green}   端口设置 (回车跳过为随机端口)     ${plain}"
    echo -e "${blue}======================================${plain}"

    read -p "设置 Vless-Reality 端口 (回车随机): " input_p_vl
    if [[ -n "$input_p_vl" ]]; then
        p_vl="$input_p_vl"
    else
        chooseport; p_vl="$port"
    fi

    read -p "设置 Vmess-WS 端口 (回车随机): " input_p_vm
    if [[ -n "$input_p_vm" ]]; then
        p_vm="$input_p_vm"
    else
        chooseport; p_vm="$port"
    fi

    read -p "设置 Hysteria2 端口 (回车随机): " input_p_hy
    if [[ -n "$input_p_hy" ]]; then
        p_hy="$input_p_hy"
    else
        chooseport; p_hy="$port"
    fi

    read -p "设置 Tuic v5 端口 (回车随机): " input_p_tc
    if [[ -n "$input_p_tc" ]]; then
        p_tc="$input_p_tc"
    else
        chooseport; p_tc="$port"
    fi

    read -p "设置 AnyTLS 端口 (回车随机): " input_p_an
    if [[ -n "$input_p_an" ]]; then
        p_an="$input_p_an"
    else
        chooseport; p_an="$port"
    fi

    # 保存端口到 ports.conf
    cat > "$PORTS_CONF" <<EOF
VL=$p_vl
VM=$p_vm
HY=$p_hy
TC=$p_tc
AN=$p_an
EOF
    log_info "端口分配: VL=$p_vl VM=$p_vm HY=$p_hy TC=$p_tc AN=$p_an"

    # 用 jq 构建 JSON
    local tmp_inbounds="/tmp/hammer_inbounds.json"
    local tmp_outbounds="/tmp/hammer_outbounds.json"
    local tmp_rules="/tmp/hammer_rules.json"

    # --- 构建 inbounds: 5 协议 ---
    jq -n '[]' > "$tmp_inbounds"

    jq --arg port "$p_vl" --arg uuid "$uuid" --arg priv "$priv_key" --arg sid "$short_id" \
       '. += [{type:"vless",tag:"in-vl",listen:"::",listen_port:($port|tonumber),users:[{uuid:$uuid,flow:"xtls-rprx-vision"}],tls:{enabled:true,server_name:"apple.com",reality:{enabled:true,handshake:{server:"apple.com",server_port:443},private_key:$priv,short_id:[$sid]}}}]' \
       "$tmp_inbounds" > "${tmp_inbounds}.tmp" && mv "${tmp_inbounds}.tmp" "$tmp_inbounds"

    jq --arg port "$p_vm" --arg uuid "$uuid" \
       '. += [{type:"vmess",tag:"in-vm",listen:"::",listen_port:($port|tonumber),users:[{uuid:$uuid,alterId:0}],transport:{type:"ws",path:"/hammer-vm"}}]' \
       "$tmp_inbounds" > "${tmp_inbounds}.tmp" && mv "${tmp_inbounds}.tmp" "$tmp_inbounds"

    jq --arg port "$p_hy" --arg uuid "$uuid" \
       '. += [{type:"hysteria2",tag:"in-hy",listen:"::",listen_port:($port|tonumber),users:[{password:$uuid}],tls:{enabled:true,server_name:"www.bing.com",certificate_path:"/etc/hammer-sb/cert.pem",key_path:"/etc/hammer-sb/key.pem"}}]' \
       "$tmp_inbounds" > "${tmp_inbounds}.tmp" && mv "${tmp_inbounds}.tmp" "$tmp_inbounds"

    jq --arg port "$p_tc" --arg uuid "$uuid" \
       '. += [{type:"tuic",tag:"in-tc",listen:"::",listen_port:($port|tonumber),users:[{uuid:$uuid,password:$uuid}],tls:{enabled:true,server_name:"www.bing.com",certificate_path:"/etc/hammer-sb/cert.pem",key_path:"/etc/hammer-sb/key.pem"}}]' \
       "$tmp_inbounds" > "${tmp_inbounds}.tmp" && mv "${tmp_inbounds}.tmp" "$tmp_inbounds"

    jq --arg port "$p_an" --arg uuid "$uuid" \
       '. += [{type:"anytls",tag:"in-an",listen:"::",listen_port:($port|tonumber),users:[{name:"user",password:$uuid}],tls:{enabled:true,server_name:"www.bing.com",certificate_path:"/etc/hammer-sb/cert.pem",key_path:"/etc/hammer-sb/key.pem"}}]' \
       "$tmp_inbounds" > "${tmp_inbounds}.tmp" && mv "${tmp_inbounds}.tmp" "$tmp_inbounds"

    # 本地混合代理，仅用于本机检测 WARP 出口 IP。
    local mixed_port=$(shuf -i 20000-30000 -n 1)
    jq --arg port "$mixed_port" \
       '. += [{type:"mixed",tag:"in-mixed",listen:"127.0.0.1",listen_port:($port|tonumber)}]' \
       "$tmp_inbounds" > "${tmp_inbounds}.tmp" && mv "${tmp_inbounds}.tmp" "$tmp_inbounds"
    echo "MIXED=$mixed_port" >> "$PORTS_CONF"

    # --- 构建 outbounds: 只有 direct + block (WARP 由选项7添加) ---
    jq -n '[{type:"direct",tag:"direct"},{type:"block",tag:"block"}]' > "$tmp_outbounds"

    # --- 构建 route rules ---
    jq -n '[]' > "$tmp_rules"

    # 5 协议入站 → direct (WARP 池添加后会改为 Warp-Pool)
    jq '. += [{inbound:["in-vl","in-vm","in-hy","in-tc","in-an"],outbound:"direct"}]' \
       "$tmp_rules" > "${tmp_rules}.tmp" && mv "${tmp_rules}.tmp" "$tmp_rules"

    # mixed 入站 → direct (WARP 池添加后会改为 Warp-Pool)
    jq '. += [{inbound:["in-mixed"],outbound:"direct"}]' \
       "$tmp_rules" > "${tmp_rules}.tmp" && mv "${tmp_rules}.tmp" "$tmp_rules"

    # DNS sniff
    jq '. += [{protocol:"dns",action:"sniff"}]' \
       "$tmp_rules" > "${tmp_rules}.tmp" && mv "${tmp_rules}.tmp" "$tmp_rules"

    # CN 直连
    jq '. += [{rule_set:["geosite-cn"],outbound:"direct"},{rule_set:["geoip-cn"],outbound:"direct"}]' \
       "$tmp_rules" > "${tmp_rules}.tmp" && mv "${tmp_rules}.tmp" "$tmp_rules"

    # --- 组装完整配置 ---
    jq -n \
       --slurpfile inbounds "$tmp_inbounds" \
       --slurpfile outbounds "$tmp_outbounds" \
       --slurpfile rules "$tmp_rules" \
       '{
         log:{level:"info",timestamp:true},
         inbounds: $inbounds[0],
         outbounds: $outbounds[0],
         route: {
           rules: $rules[0],
           rule_set: [
             {type:"remote",tag:"geosite-cn",format:"binary",url:"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",download_detour:"direct"},
             {type:"remote",tag:"geoip-cn",format:"binary",url:"https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",download_detour:"direct"}
           ],
           final:"direct",
           auto_detect_interface:true
         },
         experimental:{
           cache_file:{enabled:true,path:"/etc/hammer-sb/cache.db"},
           clash_api:{external_controller:"127.0.0.1:9090"},
           v2ray_api:{listen:"127.0.0.1:8080",stats:{enabled:true,users:[]}}
         }
       }' > "$BASE_CONF"

    rm -f "$tmp_inbounds" "$tmp_outbounds" "$tmp_rules"

    # 证书
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /etc/hammer-sb/key.pem -out /etc/hammer-sb/cert.pem -days 3650 -subj "/CN=www.bing.com" >/dev/null 2>&1

    # 初始化空 WARP 池
    echo "[]" > /etc/hammer-sb/warp_pool.json
    cp "$BASE_CONF" /etc/hammer-sb/config.json

    # 启动服务
    if systemctl is-active --quiet hammer-sb 2>/dev/null; then
        systemctl reload hammer-sb
    else
        systemctl start hammer-sb
    fi
    [[ -x /etc/hammer-sb/subscription_manager.py ]] && python3 /etc/hammer-sb/subscription_manager.py reconcile || true

    # 打印报告
    fetch_ip
    local c_addr=$(get_client_addr)
    local c_p1=$(get_client_port "$p_vl")
    local c_p2=$(get_client_port "$p_vm")
    local c_p3=$(get_client_port "$p_hy")
    local c_p4=$(get_client_port "$p_tc")
    local c_p5=$(get_client_port "$p_an")
    log_info "五协议配置完成！"
    echo -e "${blue}======================================${plain}"
    echo -e "${green}   大锤-已为您开通 5 协议     ${plain}"
    echo -e "${blue}======================================${plain}"
    echo -e "${yellow}🚀【 Vless-Reality 】${plain}端口:${green}$c_p1${plain}  Reality域名伪装地址:${green}apple.com${plain}"
    echo -e "${yellow}🚀【   Vmess-ws    】${plain}端口:${green}$c_p2${plain}  证书形式:TLS关闭  Argo状态:未开启"
    echo -e "${yellow}🚀【  Hysteria-2   】${plain}端口:${green}$c_p3${plain}  证书形式:自签证书"
    echo -e "${yellow}🚀【    Tuic-v5    】${plain}端口:${green}$c_p4${plain}  证书形式:自签证书"
    echo -e "${yellow}🚀【    Anytls     】${plain}端口:${green}$c_p5${plain}  证书形式:自签证书"
    echo -e "${blue}======================================${plain}"
    echo -e "${green}--- 节点链接 ---${plain}"
    echo -e "Vless-Reality: ${yellow}vless://$uuid@$c_addr:$c_p1?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$pub_key&sid=$short_id&type=tcp#大锤-VL${plain}"
    echo -e "Vmess-WS:      ${yellow}vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"大锤-VM\",\"add\":\"$c_addr\",\"port\":\"$c_p2\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/hammer-vm\"}" | base64 | tr -d '\n')${plain}"
    echo -e "Hysteria2:     ${yellow}hysteria2://$uuid@$c_addr:$c_p3?security=tls&sni=www.bing.com#大锤-HY${plain}"
    echo -e "Tuic v5:       ${yellow}tuic://$uuid:$uuid@$c_addr:$c_p4?sni=www.bing.com&congestion_control=bbr#大锤-TC${plain}"
    echo -e "AnyTLS:        ${yellow}anytls://user:$uuid@$c_addr:$c_p5?sni=www.bing.com#大锤-AN${plain}"
    echo -e "${blue}======================================${plain}"
    echo -e "${yellow}下一步: 通过选项7创建WARP池，域名分流和直连节点将自动生效${plain}"
    [[ "$c_addr" != "$pub_ip" ]] && echo -e "客户端地址映射: ${yellow}${c_addr}${plain} (公网IP: ${pub_ip})"
}

# WARP 池创建后，更新内部 WARP outbounds 和路由；不暴露逐路公网节点。
update_config_with_warp() {
    local pool_size=$1
    local country=$2
    local config="/etc/hammer-sb/config.json"
    local base="/etc/hammer-sb/base_config.json"

    if [[ ! -f "$config" ]]; then
        log_error "请先通过选项3初始化五协议配置。"
        return 1
    fi

    # 读取域名配置
    local warp_domains=""
    if [[ -f "$DOMAIN_CONF" ]]; then
        warp_domains=$(cat "$DOMAIN_CONF" | tr -d '\n')
    fi

    # 0. 询问域名分流策略
    local warp_domains=""
    if [[ -f "$DOMAIN_CONF" ]]; then
        warp_domains=$(cat "$DOMAIN_CONF" | tr -d '\n')
        echo -e "当前分流域名: ${yellow}${warp_domains}${plain}"
        read -p "是否修改？输入新域名或回车保持: " new_domains
        [[ -n "$new_domains" ]] && warp_domains="$new_domains"
    else
        echo ""
        echo -e "${yellow}域名分流配置 (哪些域名走 WARP，其余直连):${plain}"
        read -p "输入分流域名，多个用逗号分隔 (如 google.com,openai.com, 留空则全部走WARP): " warp_domains
    fi
    echo "$warp_domains" > "$DOMAIN_CONF"

    # 1. 注册 WARP 池
    generate_warp_pool "$pool_size" "$country"

    # 检查 WARP 池是否有效
    local pool_len=$(jq 'length' /etc/hammer-sb/warp_pool.json 2>/dev/null || echo 0)
    if [[ "$pool_len" -eq 0 ]]; then
        log_error "WARP 池注册失败，配置未更新。"
        return 1
    fi

    # 2. 清理旧的 WARP 相关配置 (endpoints + outbounds + inbounds + rules)
    # 用分步清理避免 jq 类型错误
    # 清理 endpoints
    if jq -e '.endpoints' "$config" >/dev/null 2>&1; then
        jq 'del(.endpoints[] | select(.tag | startswith("warp-pool-") or startswith("warp-wg-")))' \
           "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
    fi
    # 清理 outbounds
    jq 'del(.outbounds[] | select(.tag | startswith("warp-pool-") or startswith("warp-wg-") or .tag == "Warp-Pool"))' \
       "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
    # 清理 inbounds
    jq 'del(.inbounds[] | select(.tag | startswith("in-warp")))' \
       "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
    # 清理 route rules
    jq 'del(.route.rules[] | select((.inbound // []) | type == "array" and any(startswith("in-warp"))))' \
       "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
    jq 'del(.route.rules[] | select(.outbound == "Warp-Pool" and (.inbound // []) == ["in-vl","in-vm","in-hy","in-tc","in-an"]))' \
       "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"

    # 3. 合并 WARP endpoints (纯 WireGuard，全部放 endpoints)
    local wg_endpoints=$(cat /etc/hammer-sb/warp_pool.json)

    # 添加 endpoints (如果不存在则创建数组)
    if jq -e '.endpoints' "$config" >/dev/null 2>&1; then
        jq --argjson eps "$wg_endpoints" \
           '.endpoints += $eps' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
    else
        jq --argjson eps "$wg_endpoints" \
           '. + {endpoints:$eps}' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
    fi

    # 5. 添加 Warp-Pool selector outbound
    local pool_tags=$(for i in $(seq 1 $pool_size); do echo "\"warp-pool-$i\""; done | paste -sd, -)
    jq --argjson pts "[${pool_tags}]" \
       '.outbounds += [{type:"selector",tag:"Warp-Pool",outbounds:$pts}]' \
       "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"

    # 5. 更新路由: 5 协议入站 + mixed → Warp-Pool
    jq '(.route.rules[] | select(.inbound == ["in-vl","in-vm","in-hy","in-tc","in-an"])).outbound = "Warp-Pool"' \
       "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
    jq '(.route.rules[] | select(.inbound == ["in-mixed"])).outbound = "Warp-Pool"' \
       "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"

    # 6. 域名分流规则 → Warp-Pool
    if [[ -n "$warp_domains" ]]; then
        local domain_json=$(echo "$warp_domains" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R . | jq -sc .)
        # 删除旧域名规则再添加新的
        jq 'del(.route.rules[] | select(.domain?))' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
        jq --argjson domains "$domain_json" \
           '.route.rules += [{domain:$domains,outbound:"Warp-Pool"}]' \
           "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
    fi

    # 8. 同步 base_config
    cp "$config" "$base"

    # 9. 验证并启动
    if $SB_BINARY_PATH check -c "$config" 2>/dev/null; then
        if systemctl is-active --quiet hammer-sb 2>/dev/null; then
            systemctl reload hammer-sb
        else
            systemctl start hammer-sb
        fi
        log_info "WARP 池已添加，配置已生效！"
    else
        log_error "配置验证失败，请检查。"
        $SB_BINARY_PATH check -c "$config"
        return 1
    fi

    log_info "WARP 内部出口池已更新（未创建独立公网节点）。"
}

# 静默配置重生成 (从 protocols.conf 读取状态，无交互)
generate_config_silent() {
    local pf="/etc/hammer-sb/protocols.conf"
    if [[ ! -f "$pf" ]]; then
        log_error "协议状态文件不存在，无法静默重载。"
        return 1
    fi
    if [[ ! -f "$BASE_CONF" ]]; then
        log_error "基础配置文件不存在，请先执行全量初始化。"
        return 1
    fi

    log_info "正在根据协议状态静默重组配置..."

    local config="/etc/hammer-sb/config.json"
    local vl=$(grep '^VL=' "$pf" | cut -d= -f2)
    local vm=$(grep '^VM=' "$pf" | cut -d= -f2)
    local hy=$(grep '^HY=' "$pf" | cut -d= -f2)
    local tc=$(grep '^TC=' "$pf" | cut -d= -f2)
    local an=$(grep '^AN=' "$pf" | cut -d= -f2)

    local cache="/etc/hammer-sb/disabled_inbounds.json"
    [[ -s "$cache" ]] || echo '{}' > "$cache"
    cp "$config" "${config}.tmp" || return 1

    local spec tag state port_key saved port_value
    for spec in "in-vl:$vl:VL" "in-vm:$vm:VM" "in-hy:$hy:HY" "in-tc:$tc:TC" "in-an:$an:AN"; do
        IFS=: read -r tag state port_key <<< "$spec"
        if [[ "$state" == "0" ]]; then
            saved=$(jq -c --arg tag "$tag" '.inbounds[] | select(.tag==$tag)' "${config}.tmp" | head -n1)
            if [[ -n "$saved" ]]; then
                jq --arg tag "$tag" --argjson node "$saved" '.[$tag]=$node' "$cache" > "${cache}.tmp" && mv "${cache}.tmp" "$cache"
                jq --arg tag "$tag" '.inbounds = [.inbounds[] | select(.tag != $tag)]' "${config}.tmp" > "${config}.next" && mv "${config}.next" "${config}.tmp"
            fi
        elif ! jq -e --arg tag "$tag" '.inbounds[] | select(.tag==$tag)' "${config}.tmp" >/dev/null; then
            saved=$(jq -c --arg tag "$tag" '.[$tag] // empty' "$cache")
            [[ -n "$saved" ]] || saved=$(jq -c --arg tag "$tag" '.inbounds[] | select(.tag==$tag)' "$BASE_CONF" | head -n1)
            if [[ -z "$saved" ]]; then
                rm -f "${config}.tmp"
                log_error "无法恢复协议入站: $tag"
                return 1
            fi
            port_value=$(grep "^${port_key}=" "$PORTS_CONF" 2>/dev/null | cut -d= -f2)
            [[ "$port_value" =~ ^[0-9]+$ ]] && saved=$(jq --argjson port "$port_value" '.listen_port=$port' <<< "$saved")
            jq --argjson node "$saved" '.inbounds += [$node]' "${config}.tmp" > "${config}.next" && mv "${config}.next" "${config}.tmp"
            jq --arg tag "$tag" 'del(.[$tag])' "$cache" > "${cache}.tmp" && mv "${cache}.tmp" "$cache"
        fi
    done

    if /usr/local/bin/sing-box check -c "${config}.tmp"; then
        mv "${config}.tmp" "$config"
        if [[ -x /etc/hammer-sb/subscription_manager.py ]]; then
            python3 /etc/hammer-sb/subscription_manager.py reconcile || return 1
        else
            systemctl reload hammer-sb 2>/dev/null || systemctl start hammer-sb
        fi
        log_info "协议配置已更新并热重载。"
    else
        rm -f "${config}.tmp"
        log_error "协议配置校验失败，未应用修改。"
        return 1
    fi
}
