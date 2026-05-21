#!/bin/bash

# [大锤sand-box] 终极运维控制中心
# 模块化子菜单设计，对标 yg 脚本形态

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || readlink "$0" 2>/dev/null || echo "$0")")" && pwd)"
if [[ ! -f "$SCRIPT_DIR/core.sh" ]]; then
    SCRIPT_DIR="/root/hammer-sandbox"
fi
cd "$SCRIPT_DIR"

source ./core.sh
source ./install_sb.sh
source ./config_gen.sh
source ./warp_pool.sh
source ./sync_gitlab.sh
source ./protocol_manager.sh
source ./hammer_bench.sh

# 颜色
red='\033[31m\033[01m'
green='\033[32m\033[01m'
yellow='\033[33m\033[01m'
blue='\033[36m\033[01m'
plain='\033[0m'

update_stats() {
    detect_os
    get_vps_info
    check_versions
    get_traffic
}

# ==================== 状态区 ====================
show_status() {
    echo -e "VPS 状态区:"
    echo -e "系统: ${green}${release}${plain}  架构: ${green}${arch}${plain}  虚拟化: ${green}${virt}${plain}  BBR: ${green}${bbr_status}${plain}"
    echo -e "公网IP: ${yellow}${v4}${plain}  地区: ${blue}${region}${plain}"
    local map_addr=$(get_client_addr)
    if [[ "$map_addr" != "$v4" && -n "$v4" && "$v4" != "None" ]]; then
        echo -e "地址映射: ${yellow}${map_addr}${plain} (客户端连接地址)"
    fi
    echo -e "Sing-Box: $(systemctl is-active hammer-sb >/dev/null 2>&1 && echo -e "${green}Running${plain}" || echo -e "${red}Stopped${plain}")  内核: ${yellow}${local_sb_ver:-未安装}${plain}  最新: ${yellow}${remote_sb_ver:-N/A}${plain}"
    # 协议端口与状态
    local sb_conf="/etc/hammer-sb/config.json"
    if [[ -f "$sb_conf" ]]; then
        local p_vl=$(jq -r '.inbounds[] | select(.tag=="in-vl") | .listen_port // empty' "$sb_conf" 2>/dev/null)
        local p_vm=$(jq -r '.inbounds[] | select(.tag=="in-vm") | .listen_port // empty' "$sb_conf" 2>/dev/null)
        local p_hy=$(jq -r '.inbounds[] | select(.tag=="in-hy") | .listen_port // empty' "$sb_conf" 2>/dev/null)
        local p_tc=$(jq -r '.inbounds[] | select(.tag=="in-tc") | .listen_port // empty' "$sb_conf" 2>/dev/null)
        local p_an=$(jq -r '.inbounds[] | select(.tag=="in-an") | .listen_port // empty' "$sb_conf" 2>/dev/null)
        local p_wp=$(jq -r '[.inbounds[] | select(.tag | startswith("in-warp")) | .listen_port] | join(",")' "$sb_conf" 2>/dev/null)
        local vl_st="${green}ON${plain}" vm_st="${green}ON${plain}" hy_st="${green}ON${plain}" tc_st="${green}ON${plain}" an_st="${green}ON${plain}"
        if [[ -f "/etc/hammer-sb/protocols.conf" ]]; then
            [[ "$(grep '^VL=' /etc/hammer-sb/protocols.conf | cut -d= -f2)" == "0" ]] && vl_st="${red}OFF${plain}"
            [[ "$(grep '^VM=' /etc/hammer-sb/protocols.conf | cut -d= -f2)" == "0" ]] && vm_st="${red}OFF${plain}"
            [[ "$(grep '^HY=' /etc/hammer-sb/protocols.conf | cut -d= -f2)" == "0" ]] && hy_st="${red}OFF${plain}"
            [[ "$(grep '^TC=' /etc/hammer-sb/protocols.conf | cut -d= -f2)" == "0" ]] && tc_st="${red}OFF${plain}"
            [[ "$(grep '^AN=' /etc/hammer-sb/protocols.conf | cut -d= -f2)" == "0" ]] && an_st="${red}OFF${plain}"
        fi
        echo -e "  VL: ${vl_st}(:${p_vl:-N/A})  VM: ${vm_st}(:${p_vm:-N/A})  HY: ${hy_st}(:${p_hy:-N/A})  TC: ${tc_st}(:${p_tc:-N/A})  AN: ${an_st}(:${p_an:-N/A})"
        # WARP 状态
        local warp_domains=""
        [[ -f "/etc/hammer-sb/warp_domains.conf" ]] && warp_domains=$(cat /etc/hammer-sb/warp_domains.conf | tr -d '\n')
        local has_warp=$(jq -r '[.endpoints[]? | select(.type=="wireguard")] | length' "$sb_conf" 2>/dev/null || echo 0)
        if [[ "$has_warp" -gt 0 ]]; then
            local warp_split_st="${green}ON${plain}"
            [[ -z "$warp_domains" ]] && warp_split_st="${red}OFF${plain}"
            local warp_exit_ip=""
            if systemctl is-active --quiet hammer-sb 2>/dev/null; then
                local mixed_port=$(grep '^MIXED=' /etc/hammer-sb/ports.conf 2>/dev/null | cut -d= -f2)
                if [[ -n "$mixed_port" ]]; then
                    warp_exit_ip=$(curl -s4m3 -x http://127.0.0.1:$mixed_port icanhazip.com 2>/dev/null || echo "")
                fi
            fi
            local warp_ip_info=""
            [[ -n "$warp_exit_ip" ]] && warp_ip_info="  出口IP:${green}${warp_exit_ip}${plain}"
            echo -e "  WARP分流: ${warp_split_st}  WARP直连: ${green}${has_warp}路${plain}(:${p_wp})${warp_ip_info}"
        else
            echo -e "  WARP: ${red}未创建${plain}"
        fi
    fi
    echo -e "流量: ${yellow}${traffic_used:-N/A}${plain}/${yellow}${traffic_total:-N/A}${plain} (${yellow}${traffic_pct:-0%}${plain})  剩余: ${green}${traffic_remain:-N/A}${plain}  重置: 每月${green}${traffic_reset_day:-1号}${plain}"
}

# ==================== 主菜单 ====================
show_menu() {
    clear
    echo -e "${blue}====================================================================================${plain}"
    echo -e "         ${blue}大锤sand-box 终极运维看板${plain}    快捷: ${yellow}sb${plain}/${yellow}dc${plain}"
    echo -e "${blue}====================================================================================${plain}"
    show_status
    echo -e "${blue}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${plain}"
    echo -e "${yellow} 1.${plain} 安装/更新 Sing-box              ${yellow} 2.${plain} 卸载 Sing-box"
    echo -e " ----------------------------------------------------------------------------------"
    echo -e "${yellow} 3.${plain} 变更配置 【端口/UUID/证书/地址映射】"
    echo -e "${yellow} 4.${plain} 协议管理 【开关/重启服务】"
    echo -e "${yellow} 5.${plain} WARP 管理 【分流/直连/出口IP】"
    echo -e " ----------------------------------------------------------------------------------"
    echo -e "${yellow} 6.${plain} 订阅推送 【GitLab三合一/刷新节点】"
    echo -e "${yellow} 7.${plain} 流量管理 【配额/统计/重置】"
    echo -e "${yellow} 8.${plain} 系统优化 【BBR/内核版本/日志】"
    echo -e "${yellow} 9.${plain} VPS 体检 【回程/IP质量/跑分】"
    echo -e " ----------------------------------------------------------------------------------"
    echo -e "${yellow} 0.${plain} 退出"
    echo -e "${blue}====================================================================================${plain}"
}

# ==================== 子菜单3: 变更配置 ====================
menu_config() {
    while true; do
        clear
        echo -e "${blue}==================== 变更配置 ====================${plain}"
        echo -e "${yellow} 1.${plain} 更改五协议端口"
        echo -e "${yellow} 2.${plain} 更换全协议 UUID (密码)"
        echo -e "${yellow} 3.${plain} 更换 Vmess-WS 路径"
        echo -e "${yellow} 4.${plain} 更换 Reality 伪装域名"
        echo -e "${yellow} 5.${plain} 重新生成自签证书"
        echo -e "${yellow} 6.${plain} 设置地址映射 (NAT/VM)"
        echo -e "${yellow} 0.${plain} 返回上层"
        read -p "请选择: " c
        case $c in
            1) # 更改五协议端口
               local config="/etc/hammer-sb/config.json"
               if [[ ! -f "$config" ]]; then
                   log_error "请先初始化配置。"; read -p "按回车继续..."; continue
               fi
               echo -e "当前端口:"
               source /etc/hammer-sb/ports.conf 2>/dev/null
               echo -e "  VL:${yellow}${VL}${plain}  VM:${yellow}${VM}${plain}  HY:${yellow}${HY}${plain}  TC:${yellow}${TC}${plain}  AN:${yellow}${AN}${plain}"
               echo -e "输入新端口 (留空保持不变):"
               read -p "Vless-Reality 端口: " new_vl
               read -p "Vmess-WS 端口: " new_vm
               read -p "Hysteria2 端口: " new_hy
               read -p "Tuic v5 端口: " new_tc
               read -p "AnyTLS 端口: " new_an
               # 更新 config.json 中的端口
               [[ -n "$new_vl" ]] && jq --arg p "$new_vl" '(.inbounds[] | select(.tag=="in-vl")).listen_port = ($p|tonumber)' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config" && sed -i "s/^VL=.*/VL=$new_vl/" /etc/hammer-sb/ports.conf
               [[ -n "$new_vm" ]] && jq --arg p "$new_vm" '(.inbounds[] | select(.tag=="in-vm")).listen_port = ($p|tonumber)' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config" && sed -i "s/^VM=.*/VM=$new_vm/" /etc/hammer-sb/ports.conf
               [[ -n "$new_hy" ]] && jq --arg p "$new_hy" '(.inbounds[] | select(.tag=="in-hy")).listen_port = ($p|tonumber)' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config" && sed -i "s/^HY=.*/HY=$new_hy/" /etc/hammer-sb/ports.conf
               [[ -n "$new_tc" ]] && jq --arg p "$new_tc" '(.inbounds[] | select(.tag=="in-tc")).listen_port = ($p|tonumber)' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config" && sed -i "s/^TC=.*/TC=$new_tc/" /etc/hammer-sb/ports.conf
               [[ -n "$new_an" ]] && jq --arg p "$new_an" '(.inbounds[] | select(.tag=="in-an")).listen_port = ($p|tonumber)' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config" && sed -i "s/^AN=.*/AN=$new_an/" /etc/hammer-sb/ports.conf
               systemctl reload hammer-sb 2>/dev/null || systemctl start hammer-sb
               log_info "端口已更新并重载。"
               read -p "按回车继续..." ;;
            2) # 更换 UUID
               local config="/etc/hammer-sb/config.json"
               if [[ ! -f "$config" ]]; then
                   log_error "请先初始化配置。"; read -p "按回车继续..."; continue
               fi
               local old_uuid=$(jq -r '.inbounds[0].users[0].uuid' "$config")
               echo -e "当前UUID: ${yellow}${old_uuid}${plain}"
               read -p "输入新UUID (回车随机生成): " new_uuid
               [[ -z "$new_uuid" ]] && new_uuid=$(cat /proc/sys/kernel/random/uuid)
               # 更新所有协议的 UUID
               jq --arg uuid "$new_uuid" '(.inbounds[] | .users[]?).uuid = $uuid | (.inbounds[] | .users[]?).password = $uuid | (.inbounds[] | select(.type=="anytls") | .users[]?).password = $uuid' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
               systemctl reload hammer-sb 2>/dev/null || systemctl start hammer-sb
               log_info "UUID 已更换为: $new_uuid"
               read -p "按回车继续..." ;;
            3) # 更换 Vmess 路径
               local config="/etc/hammer-sb/config.json"
               local old_path=$(jq -r '.inbounds[] | select(.tag=="in-vm") | .transport.path // "/hammer-vm"' "$config")
               echo -e "当前Vmess路径: ${yellow}${old_path}${plain}"
               read -p "输入新路径 (如 /new-path): " new_path
               if [[ -n "$new_path" ]]; then
                   jq --arg p "$new_path" '(.inbounds[] | select(.tag=="in-vm")).transport.path = $p' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
                   systemctl reload hammer-sb 2>/dev/null || systemctl start hammer-sb
                   log_info "Vmess 路径已更换为: $new_path"
               fi
               read -p "按回车继续..." ;;
            4) # 更换 Reality 伪装域名
               local config="/etc/hammer-sb/config.json"
               local old_sni=$(jq -r '.inbounds[] | select(.tag=="in-vl") | .tls.server_name // "apple.com"' "$config")
               echo -e "当前伪装域名: ${yellow}${old_sni}${plain}"
               read -p "输入新伪装域名 (如 www.microsoft.com): " new_sni
               if [[ -n "$new_sni" ]]; then
                   jq --arg sni "$new_sni" --argjson port 443 \
                      '(.inbounds[] | select(.tag=="in-vl")).tls.server_name = $sni | (.inbounds[] | select(.tag=="in-vl")).tls.reality.handshake.server = $sni | (.inbounds[] | select(.tag=="in-vl")).tls.reality.handshake.server_port = $port' \
                      "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
                   systemctl reload hammer-sb 2>/dev/null || systemctl start hammer-sb
                   log_info "伪装域名已更换为: $new_sni"
               fi
               read -p "按回车继续..." ;;
            5) # 重新生成自签证书
               openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /etc/hammer-sb/key.pem -out /etc/hammer-sb/cert.pem -days 3650 -subj "/CN=www.bing.com" >/dev/null 2>&1
               systemctl reload hammer-sb 2>/dev/null
               log_info "自签证书已重新生成。"
               read -p "按回车继续..." ;;
            6) set_addr_map; read -p "按回车继续..." ;;
            0) return ;;
        esac
    done
}

# ==================== 子菜单4: 协议管理 ====================
menu_proto() {
    while true; do
        clear
        echo -e "${blue}==================== 协议管理 ====================${plain}"
        echo -e "${yellow} 1.${plain} 协议开关管理"
        echo -e "${yellow} 2.${plain} 五协议初始化 (重置配置)"
        echo -e "${yellow} 3.${plain} 启动/重启 Sing-box"
        echo -e "${yellow} 4.${plain} 停止 Sing-box"
        echo -e "${yellow} 0.${plain} 返回上层"
        read -p "请选择: " c
        case $c in
            1) manage_protocols ;;
            2) generate_config; read -p "按回车继续..." ;;
            3) systemctl restart hammer-sb 2>/dev/null || systemctl start hammer-sb
               log_info "Sing-box 已重启。"
               read -p "按回车继续..." ;;
            4) systemctl stop hammer-sb 2>/dev/null
               log_info "Sing-box 已停止。"
               read -p "按回车继续..." ;;
            0) return ;;
        esac
    done
}

# ==================== 子菜单5: WARP 管理 ====================
menu_warp() {
    while true; do
        clear
        echo -e "${blue}==================== WARP 管理 ====================${plain}"
        local sb_conf="/etc/hammer-sb/config.json"
        local has_warp=0
        [[ -f "$sb_conf" ]] && has_warp=$(jq -r '[.endpoints[]? | select(.type=="wireguard")] | length' "$sb_conf" 2>/dev/null || echo 0)
        local warp_domains=""
        [[ -f "/etc/hammer-sb/warp_domains.conf" ]] && warp_domains=$(cat /etc/hammer-sb/warp_domains.conf | tr -d '\n')
        if [[ "$has_warp" -gt 0 ]]; then
            local warp_split_st="${green}已开启${plain}"
            [[ -z "$warp_domains" ]] && warp_split_st="${red}未配置域名${plain}"
            echo -e "WARP分流: ${warp_split_st}  域名: ${yellow}${warp_domains:-无}${plain}"
            echo -e "WARP直连: ${green}${has_warp}路${plain}"
        else
            echo -e "WARP: ${red}未创建${plain}"
        fi
        echo -e "${blue}--------------------------------------------------${plain}"
        echo -e "${yellow} 1.${plain} WARP 分流开关/域名配置"
        echo -e "${yellow} 2.${plain} WARP 直连节点管理 (创建/增减)"
        echo -e "${yellow} 3.${plain} 触发 WARP IP 旋转"
        echo -e "${yellow} 4.${plain} 查看 WARP 出口 IP / 解锁状态"
        echo -e "${yellow} 0.${plain} 返回上层"
        read -p "请选择: " c
        case $c in
            1) # 分流配置
               echo -e "当前分流域名: ${yellow}${warp_domains:-未配置}${plain}"
               echo -e "留空则全部流量走WARP，配置域名后仅指定域名走WARP其余直连"
               read -p "输入分流域名 (多个逗号分隔, 留空取消): " new_domains
               if [[ -n "$new_domains" ]]; then
                   echo "$new_domains" > /etc/hammer-sb/warp_domains.conf
                   local config="/etc/hammer-sb/config.json"
                   if [[ -f "$config" ]]; then
                       jq 'del(.route.rules[] | select(.domain?))' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
                       local domain_json=$(echo "$new_domains" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R . | jq -sc .)
                       local ob="direct"
                       [[ "$has_warp" -gt 0 ]] && ob="Warp-Pool"
                       jq --argjson domains "$domain_json" --arg ob "$ob" \
                          '.route.rules += [{domain:$domains,outbound:$ob}]' \
                          "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
                       if [[ "$has_warp" -gt 0 ]]; then
                           jq '(.route.rules[] | select(.inbound == ["in-vl","in-vm","in-hy","in-tc","in-an"])).outbound = "Warp-Pool"' \
                              "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
                       fi
                       systemctl reload hammer-sb 2>/dev/null || systemctl start hammer-sb
                       log_info "分流域名已更新。"
                   fi
               fi
               read -p "按回车继续..." ;;
            2) # WARP 直连节点
               read -p "输入WARP路数 (1-10, 默认3): " ps; ps=${ps:-3}
               read -p "指定出口国家 (如 US/JP/SG, 留空原生WARP): " psc
               update_config_with_warp $ps "$psc"
               read -p "按回车继续..." ;;
            3) bash ./warp_rotate.sh; read -p "已旋转...按回车继续..." ;;
            4) # 查看出口 IP
               local mixed_port=$(grep '^MIXED=' /etc/hammer-sb/ports.conf 2>/dev/null | cut -d= -f2)
               if [[ -n "$mixed_port" ]] && systemctl is-active --quiet hammer-sb 2>/dev/null; then
                   local exit_ip=$(curl -s4m3 -x http://127.0.0.1:$mixed_port icanhazip.com 2>/dev/null || echo "检测失败")
                   echo -e "WARP出口IP: ${green}${exit_ip}${plain}"
                   # Netflix 解锁检测
                   local nf=$(curl -s4m3 -x http://127.0.0.1:$mixed_port https://www.netflix.com/title/80018499 2>/dev/null | head -1)
                   if [[ -n "$nf" ]]; then
                       echo -e "Netflix: ${green}已解锁${plain}"
                   else
                       echo -e "Netflix: ${red}未解锁${plain}"
                   fi
               else
                   echo -e "${red}WARP 未运行或 mixed 代理未配置${plain}"
               fi
               read -p "按回车继续..." ;;
            0) return ;;
        esac
    done
}

# ==================== 子菜单6: 订阅推送 ====================
menu_sub() {
    while true; do
        clear
        echo -e "${blue}==================== 订阅推送 ====================${plain}"
        local gl_conf="/etc/hammer-sb/gitlab.conf"
        if [[ -f "$gl_conf" ]]; then
            source "$gl_conf"
            echo -e "GitLab: ${green}${USERID}/${PROJECT}${plain} 分支: ${yellow}${BRANCH:-main}${plain}"
            local sb_link=$(cat /etc/hammer-sb/sing_box_gitlab.txt 2>/dev/null)
            [[ -n "$sb_link" ]] && echo -e "SB订阅: ${yellow}${sb_link}${plain}"
        else
            echo -e "GitLab: ${red}未配置${plain}"
        fi
        echo -e "${blue}--------------------------------------------------${plain}"
        echo -e "${yellow} 1.${plain} 刷新并推送订阅 (三合一)"
        echo -e "${yellow} 2.${plain} 设置/重置 GitLab 订阅推送"
        echo -e "${yellow} 3.${plain} 查看订阅链接"
        echo -e "${yellow} 0.${plain} 返回上层"
        read -p "请选择: " c
        case $c in
            1) sync_to_gitlab; read -p "按回车继续..." ;;
            2) setup_gitlab; read -p "按回车继续..." ;;
            3) show_sub_links 2>/dev/null; print_local_paths; read -p "按回车继续..." ;;
            0) return ;;
        esac
    done
}

# ==================== 子菜单7: 流量管理 ====================
menu_traffic() {
    while true; do
        clear
        echo -e "${blue}==================== 流量管理 ====================${plain}"
        get_traffic
        echo -e "配额: ${yellow}${traffic_total:-N/A}${plain}  已用: ${red}${traffic_used:-N/A}${plain} (${yellow}${traffic_pct:-0%}${plain})  剩余: ${green}${traffic_remain:-N/A}${plain}"
        echo -e "重置周期: 每月 ${green}${traffic_reset_day:-1号}${plain}  上行: ${yellow}${traffic_up:-N/A}${plain}  下行: ${green}${traffic_down:-N/A}${plain}"
        echo -e "${blue}--------------------------------------------------${plain}"
        echo -e "${yellow} 1.${plain} 设置流量配额"
        echo -e "${yellow} 2.${plain} 手动重置流量统计"
        echo -e "${yellow} 0.${plain} 返回上层"
        read -p "请选择: " c
        case $c in
            1) read -p "设置总流量配额 (GB, 默认500): " tg
                tg=${tg:-500}
                read -p "设置每月重置日 (1-28, 默认1号): " rd
                rd=${rd:-1}
                cat > /etc/hammer-sb/quota.conf <<EOF
TOTAL_GB=$tg
RESET_DAY=$rd
EOF
                log_info "配额已更新: 总额 ${tg}GB, 每月${rd}号重置。"
                read -p "按回车继续..." ;;
            2) rm -f /etc/hammer-sb/usage.db
                log_info "流量统计已手动重置。"
                read -p "按回车继续..." ;;
            0) return ;;
        esac
    done
}

# ==================== 子菜单8: 系统优化 ====================
menu_system() {
    while true; do
        clear
        echo -e "${blue}==================== 系统优化 ====================${plain}"
        echo -e "${yellow} 1.${plain} 开启/重置 TCP BBR 加速"
        echo -e "${yellow} 2.${plain} 更新/切换 Sing-box 内核版本"
        echo -e "${yellow} 3.${plain} 查看 Sing-box 运行日志"
        echo -e "${yellow} 4.${plain} 启动/重启 Web UI 仪表盘"
        echo -e "${yellow} 5.${plain} 设置/修改 Web UI 密码"
        echo -e "${yellow} 0.${plain} 返回上层"
        read -p "请选择: " c
        case $c in
            1) enable_bbr; read -p "按回车继续..." ;;
            2) install_kernel; setup_service; read -p "按回车继续..." ;;
            3) journalctl -u hammer-sb -f -n 20 ;;
            4) mkdir -p /etc/hammer-sb/ui/api
                cp "$SCRIPT_DIR/hammer_web_ui.html" /etc/hammer-sb/ui/index.html 2>/dev/null || cp ./hammer_web_ui.html /etc/hammer-sb/ui/index.html
                cp "$SCRIPT_DIR/hammer_web_actiond.sh" /etc/hammer-sb/ui/ 2>/dev/null || cp ./hammer_web_actiond.sh /etc/hammer-sb/ui/
                cp "$SCRIPT_DIR/hammer_web_state.sh" /etc/hammer-sb/ui/ 2>/dev/null || cp ./hammer_web_state.sh /etc/hammer-sb/ui/
                chmod +x /etc/hammer-sb/ui/*.sh
                bash /etc/hammer-sb/ui/hammer_web_actiond.sh restart
                (crontab -l 2>/dev/null | grep -v "hammer_web_state"; echo "* * * * * bash /etc/hammer-sb/ui/hammer_web_state.sh >> /var/log/hammer-web-state.log 2>&1") | crontab -
                systemctl reload hammer-sb 2>/dev/null
                log_info "Web UI 已部署。访问 http://$(get_client_addr):9090"
                read -p "按回车继续..." ;;
            5) read -sp "设置 Web UI 管理密码 (留空则清除密码): " ui_pass
                echo ""
                if [[ -z "$ui_pass" ]]; then
                    rm -f /etc/hammer-sb/ui_pass.conf
                    log_info "密码已清除。"
                else
                    echo "$ui_pass" > /etc/hammer-sb/ui_pass.conf
                    chmod 600 /etc/hammer-sb/ui_pass.conf
                    log_info "密码已设置。"
                fi
                read -p "按回车继续..." ;;
            0) return ;;
        esac
    done
}

# ==================== 子菜单9: VPS 体检 ====================
menu_bench() {
    while true; do
        show_bench_menu
        read -p "请输入编号 (0返回): " bchoice
        [[ "$bchoice" == "0" ]] && break
        run_bench "$bchoice"
    done
}

# ==================== 主循环 ====================
main() {
    update_stats
    while true; do
        show_menu
        read -p "请输入对应的操作编号: " choice
        case $choice in
            1) install_base_deps; install_kernel; setup_service; read -p "完成，按回车键继续..." ;;
            2) uninstall_sb; read -p "完成，按回车键继续..." ;;
            3) menu_config ;;
            4) menu_proto ;;
            5) menu_warp ;;
            6) menu_sub ;;
            7) menu_traffic ;;
            8) menu_system ;;
            9) menu_bench ;;
            0) exit 0 ;;
            *) sleep 1 ;;
        esac
    done
}

main
