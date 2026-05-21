#!/bin/bash

# [大锤sand-box] 协议可视化管理中心 (Protocol Control Center)
# 实现二级菜单开关逻辑

source ./core.sh
source ./config_gen.sh

STATUS_FILE="/etc/hammer-sb/protocols.conf"

# 初始化状态文件 (如果不存在)
init_status() {
    if [[ ! -f "$STATUS_FILE" ]]; then
        echo "VL=1" > "$STATUS_FILE"
        echo "VM=1" >> "$STATUS_FILE"
        echo "HY=1" >> "$STATUS_FILE"
        echo "TC=1" >> "$STATUS_FILE"
        echo "AN=1" >> "$STATUS_FILE"
    fi
}

# 获取单协议状态
get_st() {
    grep "$1=" "$STATUS_FILE" | cut -d= -f2
}

# 协议管理子菜单
manage_protocols() {
    init_status
    while true; do
        vl_s=$(get_st VL); vm_s=$(get_st VM); hy_s=$(get_st HY); tc_s=$(get_st TC); an_s=$(get_st AN)
        
        clear
        echo -e "${blue}======================================${plain}"
        echo -e "       ${blue}二级管理：协议开关大厅${plain}           "
        echo -e "${blue}======================================${plain}"
        echo -e " 1. [$( [[ $vl_s == 1 ]] && echo -e "${green}ON${plain}" || echo -e "${red}OFF${plain}") ] Vless-Reality"
        echo -e " 2. [$( [[ $vm_s == 1 ]] && echo -e "${green}ON${plain}" || echo -e "${red}OFF${plain}") ] Vmess-WS"
        echo -e " 3. [$( [[ $hy_s == 1 ]] && echo -e "${green}ON${plain}" || echo -e "${red}OFF${plain}") ] Hysteria2"
        echo -e " 4. [$( [[ $tc_s == 1 ]] && echo -e "${green}ON${plain}" || echo -e "${red}OFF${plain}") ] Tuic v5"
        echo -e " 5. [$( [[ $an_s == 1 ]] && echo -e "${green}ON${plain}" || echo -e "${red}OFF${plain}") ] AnyTLS"
        echo -e " --------------------------------------"
        echo -e " 0. 返回主菜单"
        echo -e "${blue}======================================${plain}"
        
        read -p "请输入对应的编号切换状态: " pchoice
        case $pchoice in
            1) [[ $vl_s == 1 ]] && sed -i 's/VL=1/VL=0/' "$STATUS_FILE" || sed -i 's/VL=0/VL=1/' "$STATUS_FILE" ;;
            2) [[ $vm_s == 1 ]] && sed -i 's/VM=1/VM=0/' "$STATUS_FILE" || sed -i 's/VM=0/VM=1/' "$STATUS_FILE" ;;
            3) [[ $hy_s == 1 ]] && sed -i 's/HY=1/HY=0/' "$STATUS_FILE" || sed -i 's/HY=0/HY=1/' "$STATUS_FILE" ;;
            4) [[ $tc_s == 1 ]] && sed -i 's/TC=1/TC=0/' "$STATUS_FILE" || sed -i 's/TC=0/TC=1/' "$STATUS_FILE" ;;
            5) [[ $an_s == 1 ]] && sed -i 's/AN=1/AN=0/' "$STATUS_FILE" || sed -i 's/AN=0/AN=1/' "$STATUS_FILE" ;;
            0) break ;;
        esac
        
        # 实时同步配置并重载 (Silent Reload)
        log_info "正在为您切换内核配置..."
        # 这里需要 config_gen.sh 支持从 protocols.conf 读取状态
        generate_config_silent
    done
}
