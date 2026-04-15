#!/bin/bash

# [大锤sand-box] 终极运维控制中心
# 对标 yg 脚本形态，支持二级开关与快捷启动

source ./core.sh
source ./install_sb.sh
source ./config_gen.sh
source ./warp_pool.sh
source ./sync_gitlab.sh
source ./protocol_manager.sh

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
}

show_menu() {
    clear
    echo -e "${blue}====================================================================================${plain}"
    echo -e "         ${blue}大锤sand-box 终极运维看板${plain}              "
    echo -e "${blue}====================================================================================${plain}"
    echo -e "当前脚本版本: ${green}v1.1.0${plain}    快捷启动命令: ${yellow}sb${plain} 或 ${yellow}dc${plain}"
    echo -e "当前内核版本: ${yellow}${local_sb_ver:-未安装}${plain}    最新内核版本: ${yellow}${remote_sb_ver:-N/A}${plain}"
    echo -e "${blue}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${plain}"
    echo -e " 1. 安装/更新 内核                   2. 彻底卸载 (清理环境)"
    echo -e " ----------------------------------------------------------------------------------"
    echo -e " 3. 五协议初始化 (全量配置)          4. [进入子菜单] 协议开关管理 (耳机开关)"
    echo -e " 5. 变更分流域名 (WARP 托管)         6. 开启/重置 TCP BBR 加速"
    echo -e " 7. 管理 WARP 并发池 (1-10路)        8. 触发 IP 强制旋转 (物理换IP)"
    echo -e " 9. 推送全能订阅 (三合一)            10. 查看实时运行日志"
    echo -e " ----------------------------------------------------------------------------------"
    echo -e " 0. 退出管理脚本"
    echo -e "${blue}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${plain}"
    echo -e "VPS 状态区:"
    echo -e "系统: ${green}${release}${plain}  架构: ${green}${arch}${plain}  虚拟化: ${green}${virt}${plain}  BBR算法: ${green}${bbr_status}${plain}"
    echo -e "公网 IPV4: ${yellow}${v4}${plain}    地区: ${blue}${region}${plain}"
    echo -e "Sing-Box 运行状态: $(systemctl is-active hammer-sb >/dev/null 2>&1 && echo -e "${green}Running${plain}" || echo -e "${red}Stopped${plain}")"
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
            7) source ./warp_pool.sh; read -p "输入路数: " ps; generate_warp_pool $ps; bash ./re-assemble.sh; read -p "完成..." ;;
            8) bash ./warp_rotate.sh; read -p "已旋转..." ;;
            9) sync_to_gitlab; read -p "完成..." ;;
            10) journalctl -u hammer-sb -f -n 20 ;;
            0) exit 0 ;;
            *) sleep 1 ;;
        esac
    done
}

main
