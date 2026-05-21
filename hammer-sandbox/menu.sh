#!/bin/bash

# [大锤sand-box] 终极运维控制中心
# 对标 yg 脚本形态，支持二级开关与快捷启动

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

show_menu() {
    clear
    echo -e "${blue}====================================================================================${plain}"
    echo -e "         ${blue}大锤sand-box 终极运维看板${plain}              "
    echo -e "${blue}====================================================================================${plain}"
    echo -e "当前脚本版本: ${green}v1.2.0${plain}    快捷启动命令: ${yellow}sb${plain} 或 ${yellow}dc${plain}"
    echo -e "当前内核版本: ${yellow}${local_sb_ver:-未安装}${plain}    最新内核版本: ${yellow}${remote_sb_ver:-N/A}${plain}"
    echo -e "${blue}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${plain}"
    echo -e " 1. 安装/更新 内核                   2. 彻底卸载 (清理环境)"
    echo -e " ----------------------------------------------------------------------------------"
    echo -e " 3. 五协议初始化                     4. 协议开关管理"
    echo -e " 5. WARP 分流配置                    6. 开启/重置 TCP BBR 加速"
    echo -e " 7. WARP 直连节点管理                8. 触发 IP 强制旋转"
    echo -e " 9. 推送全能订阅 (三合一)            10. 查看实时运行日志"
    echo -e " 11. 设置流量配额                    12. 手动重置流量统计"
    echo -e " 13. 启动/重启 Web UI 仪表盘         14. 设置/修改 Web UI 密码"
    echo -e " 15. [VPS 体检中心] 回程/IP质量/跑分  16. 设置地址映射 (NAT/VM)"
    echo -e " ----------------------------------------------------------------------------------"
    echo -e " 0. 退出管理脚本"
    echo -e "${blue}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${plain}"
    echo -e "VPS 状态区:"
    echo -e "系统: ${green}${release}${plain}  架构: ${green}${arch}${plain}  虚拟化: ${green}${virt}${plain}  BBR算法: ${green}${bbr_status}${plain}"
    echo -e "公网 IPV4: ${yellow}${v4}${plain}    地区: ${blue}${region}${plain}"
    local map_addr=$(get_client_addr)
    if [[ "$map_addr" != "$v4" && -n "$v4" && "$v4" != "None" ]]; then
        echo -e "地址映射:   ${yellow}${map_addr}${plain} (客户端使用此地址连接)"
    fi
    echo -e "Sing-Box 运行状态: $(systemctl is-active hammer-sb >/dev/null 2>&1 && echo -e "${green}Running${plain}" || echo -e "${red}Stopped${plain}")"
    # 协议端口与状态
    local sb_conf="/etc/hammer-sb/config.json"
    if [[ -f "$sb_conf" ]]; then
        local p_vl=$(jq -r '.inbounds[] | select(.tag=="in-vl") | .listen_port // empty' "$sb_conf" 2>/dev/null)
        local p_vm=$(jq -r '.inbounds[] | select(.tag=="in-vm") | .listen_port // empty' "$sb_conf" 2>/dev/null)
        local p_hy=$(jq -r '.inbounds[] | select(.tag=="in-hy") | .listen_port // empty' "$sb_conf" 2>/dev/null)
        local p_tc=$(jq -r '.inbounds[] | select(.tag=="in-tc") | .listen_port // empty' "$sb_conf" 2>/dev/null)
        local p_an=$(jq -r '.inbounds[] | select(.tag=="in-an") | .listen_port // empty' "$sb_conf" 2>/dev/null)
        local p_wp=$(jq -r '[.inbounds[] | select(.tag | startswith("in-warp")) | .listen_port] | join(",")' "$sb_conf" 2>/dev/null)
        # ON=绿色, OFF=红色
        local vl_st="${green}ON${plain}" vm_st="${green}ON${plain}" hy_st="${green}ON${plain}" tc_st="${green}ON${plain}" an_st="${green}ON${plain}"
        if [[ -f "/etc/hammer-sb/protocols.conf" ]]; then
            [[ "$(grep '^VL=' /etc/hammer-sb/protocols.conf | cut -d= -f2)" == "0" ]] && vl_st="${red}OFF${plain}"
            [[ "$(grep '^VM=' /etc/hammer-sb/protocols.conf | cut -d= -f2)" == "0" ]] && vm_st="${red}OFF${plain}"
            [[ "$(grep '^HY=' /etc/hammer-sb/protocols.conf | cut -d= -f2)" == "0" ]] && hy_st="${red}OFF${plain}"
            [[ "$(grep '^TC=' /etc/hammer-sb/protocols.conf | cut -d= -f2)" == "0" ]] && tc_st="${red}OFF${plain}"
            [[ "$(grep '^AN=' /etc/hammer-sb/protocols.conf | cut -d= -f2)" == "0" ]] && an_st="${red}OFF${plain}"
        fi
        echo -e "  Vless-Reality: ${vl_st}  端口:${yellow}${p_vl:-N/A}${plain}"
        echo -e "  Vmess-WS:      ${vm_st}  端口:${yellow}${p_vm:-N/A}${plain}"
        echo -e "  Hysteria2:     ${hy_st}  端口:${yellow}${p_hy:-N/A}${plain}"
        echo -e "  Tuic v5:       ${tc_st}  端口:${yellow}${p_tc:-N/A}${plain}"
        echo -e "  AnyTLS:        ${an_st}  端口:${yellow}${p_an:-N/A}${plain}"
        # WARP 状态
        local warp_domains=""
        [[ -f "/etc/hammer-sb/warp_domains.conf" ]] && warp_domains=$(cat /etc/hammer-sb/warp_domains.conf | tr -d '\n')
        local has_warp=$(jq -r '[.endpoints[]? | select(.type=="wireguard")] | length' "$sb_conf" 2>/dev/null || echo 0)
        if [[ "$has_warp" -gt 0 ]]; then
            local warp_split_st="${green}ON${plain}"
            [[ -z "$warp_domains" ]] && warp_split_st="${red}OFF${plain}"
            echo -e "  WARP分流:      ${warp_split_st}  域名:${yellow}${warp_domains:-未配置}${plain}"
            echo -e "  WARP直连:      ${green}$has_warp 路${plain}  端口:${yellow}${p_wp}${plain}"
        else
            echo -e "  WARP:          ${red}未创建${plain} (通过选项5/7配置)"
        fi
    fi
    echo -e "流量配额: ${yellow}${traffic_total:-N/A}${plain}  |  已用: ${red}${traffic_used:-N/A}${plain} (${yellow}${traffic_pct:-0%}${plain})  |  剩余: ${green}${traffic_remain:-N/A}${plain}"
    echo -e "重置周期: 每月 ${green}${traffic_reset_day:-1号}${plain}  |  上行: ${yellow}${traffic_up:-N/A}${plain}  |  下行: ${green}${traffic_down:-N/A}${plain}"
    echo -e "${blue}====================================================================================${plain}"
}

main() {
    update_stats
    while true; do
        show_menu
        read -p "请输入对应的操作编号: " choice
        case $choice in
            1) install_base_deps; install_kernel; setup_service; read -p "完成，按回车键继续..." ;;
            2) uninstall_sb; read -p "完成，按回车键继续..." ;;
            3) generate_config; read -p "完成，按回车键继续..." ;;
            4) manage_protocols ;;
            5) # WARP 分流配置
               local warp_domains=""
               [[ -f "/etc/hammer-sb/warp_domains.conf" ]] && warp_domains=$(cat /etc/hammer-sb/warp_domains.conf | tr -d '\n')
               echo -e "当前分流域名: ${yellow}${warp_domains:-未配置}${plain}"
               echo -e "留空则全部流量走WARP，配置域名后仅指定域名走WARP其余直连"
               read -p "输入分流域名 (多个逗号分隔, 留空取消): " new_domains
               if [[ -n "$new_domains" ]]; then
                   echo "$new_domains" > /etc/hammer-sb/warp_domains.conf
                   # 更新路由规则
                   local config="/etc/hammer-sb/config.json"
                   if [[ -f "$config" ]]; then
                       # 先删除旧的域名规则
                       jq 'del(.route.rules[] | select(.domain?))' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
                       # 添加新域名规则
                       local domain_json=$(echo "$new_domains" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R . | jq -sc .)
                       local has_warp=$(jq -r '[.endpoints[]? | select(.type=="wireguard")] | length' "$config" 2>/dev/null || echo 0)
                       local ob="direct"
                       [[ "$has_warp" -gt 0 ]] && ob="Warp-Pool"
                       jq --argjson domains "$domain_json" --arg ob "$ob" \
                          '.route.rules += [{domain:$domains,outbound:$ob}]' \
                          "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
                       # 如果有 WARP，5协议入站也改为 Warp-Pool
                       if [[ "$has_warp" -gt 0 ]]; then
                           jq '(.route.rules[] | select(.inbound == ["in-vl","in-vm","in-hy","in-tc","in-an"])).outbound = "Warp-Pool"' \
                              "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
                       fi
                       systemctl reload hammer-sb 2>/dev/null || systemctl start hammer-sb
                       log_info "分流域名已更新为: $new_domains，已重载。"
                   fi
               fi
               read -p "按回车键继续..." ;;
            6) enable_bbr; read -p "完成，按回车键继续..." ;;
            7) # WARP 直连节点管理
               read -p "输入WARP路数 (1-10, 默认3): " ps; ps=${ps:-3}
               read -p "Psiphon指定国家 (如 US/JP/SG, 留空为原生WARP): " psc
               source ./config_gen.sh; update_config_with_warp $ps "$psc"
               read -p "完成..." ;;
            8) bash ./warp_rotate.sh; read -p "已旋转..." ;;
            9) sync_to_gitlab; read -p "完成..." ;;
            10) journalctl -u hammer-sb -f -n 20 ;;
            11) read -p "设置总流量配额 (GB, 默认500): " tg
                tg=${tg:-500}
                read -p "设置每月重置日 (1-28, 默认1号): " rd
                rd=${rd:-1}
                cat > /etc/hammer-sb/quota.conf <<EOF
TOTAL_GB=$tg
RESET_DAY=$rd
EOF
                log_info "配额已更新: 总额 ${tg}GB, 每月${rd}号重置。"
                read -p "按回车键继续..." ;;
            12) rm -f /etc/hammer-sb/usage.db
                log_info "流量统计已手动重置。"
                read -p "按回车键继续..." ;;
            13) mkdir -p /etc/hammer-sb/ui/api
                cp "$(dirname "$0")/hammer_web_ui.html" /etc/hammer-sb/ui/index.html 2>/dev/null || cp ./hammer_web_ui.html /etc/hammer-sb/ui/index.html
                cp "$(dirname "$0")/hammer_web_actiond.sh" /etc/hammer-sb/ui/ 2>/dev/null || cp ./hammer_web_actiond.sh /etc/hammer-sb/ui/
                cp "$(dirname "$0")/hammer_web_state.sh" /etc/hammer-sb/ui/ 2>/dev/null || cp ./hammer_web_state.sh /etc/hammer-sb/ui/
                chmod +x /etc/hammer-sb/ui/*.sh
                bash /etc/hammer-sb/ui/hammer_web_actiond.sh restart
                (crontab -l 2>/dev/null | grep -v "hammer_web_state"; echo "* * * * * bash /etc/hammer-sb/ui/hammer_web_state.sh >> /var/log/hammer-web-state.log 2>&1") | crontab -
                systemctl reload hammer-sb 2>/dev/null
                log_info "Web UI 已部署。访问 http://$(get_client_addr):9090 查看仪表盘。"
                read -p "按回车键继续..." ;;
            14) read -sp "设置 Web UI 管理密码 (留空则清除密码): " ui_pass
                echo ""
                if [[ -z "$ui_pass" ]]; then
                    rm -f /etc/hammer-sb/ui_pass.conf
                    log_info "密码已清除，Web UI 无需密码即可访问。"
                else
                    echo "$ui_pass" > /etc/hammer-sb/ui_pass.conf
                    chmod 600 /etc/hammer-sb/ui_pass.conf
                    log_info "密码已设置。"
                fi
                read -p "按回车键继续..." ;;
            15) while true; do
                    show_bench_menu
                    read -p "请输入编号: " bchoice
                    [[ "$bchoice" == "0" ]] && break
                    run_bench "$bchoice"
                done ;;
            16) set_addr_map; read -p "按回车键继续..." ;;
            0) exit 0 ;;
            *) sleep 1 ;;
        esac
    done
}

main
