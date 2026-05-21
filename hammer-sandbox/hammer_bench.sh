#!/bin/bash

# [大锤sand-box] VPS 体检中心 (Benchmark & Check Center)
# 集成主流开源测试脚本，直接调上游最新版

source ./core.sh

show_bench_menu() {
    clear
    echo -e "${blue}========================================${plain}"
    echo -e "       ${blue}大锤 VPS 体检中心${plain}           "
    echo -e "${blue}========================================${plain}"
    echo -e "--- 网络篇 ---"
    echo -e " 1. 三网回程路由 (电信/联通/移动 traceroute)"
    echo -e " 2. 三网去程路由 (广州→你 VPS)"
    echo -e " 3. 国际主流网站互联测试 (CDN/网站延迟)"
    echo -e ""
    echo -e "--- IP 质量篇 ---"
    echo -e " 4. IP 质量检测 (46项: 黑名单/代理/VPN/威胁)"
    echo -e " 5. 流媒体解锁检测 (Netflix/Disney/YouTube/ChatGPT)"
    echo -e ""
    echo -e "--- 性能篇 ---"
    echo -e " 6. 基础跑分 (tcp-rr: CPU/IO/带宽速览)"
    echo -e " 7. YABS 跑分 (fio磁盘/Geekbench/带宽)"
    echo -e ""
    echo -e "--- 一键全测 ---"
    echo -e " 8. 融合怪全量检测 (全部打包, 约 ~20分钟)"
    echo -e ""
    echo -e " 0. 返回主菜单"
    echo -e "${blue}========================================${plain}"
    echo -e "所有脚本均调用上游原作者最新版，无需本地维护。"
    echo -e "${blue}========================================${plain}"
}

run_bench() {
    local choice=$1
    case $choice in
        1)
            log_info "正在运行: 三网回程路由 (spiritLHLS/ecs)"
            echo ""
            curl -sL "https://raw.githubusercontent.com/spiritLHLS/ecs/main/backtrace" | bash
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        2)
            log_info "正在运行: 三网去程路由 (OneClickVirt/ecsspeed)"
            echo ""
            # 去程测试: 从广州三网机房到你 VPS
            bash <(curl -sL bash.icu/ecsspeed) 2>/dev/null || \
            curl -sL "https://raw.githubusercontent.com/oneclickvirt/ecsspeed/main/ecsspeed.sh" | bash
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        3)
            log_info "正在运行: 国际主流网站互联测试 (OneClickVirt/cdn)"
            echo ""
            curl -sL "https://raw.githubusercontent.com/oneclickvirt/cdn/main/cdn.sh" | bash
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        4)
            log_info "正在运行: IP 质量检测 (oneclickvirt/ipcheck)"
            echo ""
            bash <(curl -sL "https://raw.githubusercontent.com/oneclickvirt/ipcheck/main/ipcheck.sh") 2>/dev/null || \
            bash <(curl -sL "https://raw.githubusercontent.com/spiritLHLS/ecs/main/ipcheck.sh")
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        5)
            log_info "正在运行: 流媒体解锁检测"
            echo ""
            # lmc999 脚本: 覆盖 Netflix/Disney+/YouTube/ChatGPT/Claude 等
            bash <(curl -sL "https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh") 2>/dev/null || \
            bash <(curl -sL "https://raw.githubusercontent.com/nkeonkeo/MediaUnlockTest/main/check.sh")
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        6)
            log_info "正在运行: 基础跑分 (teddysun/bench)"
            echo ""
            curl -sL "https://raw.githubusercontent.com/teddysun/across/master/bench.sh" | bash
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        7)
            log_info "正在运行: YABS 跑分 (masonr/yabs)"
            echo ""
            curl -sL yabs.sh | bash
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        8)
            log_info "正在运行: 融合怪全量检测 (spiritLHLS/ecs)"
            echo ""
            log_warn "此检测耗时约 15-25 分钟，请耐心等待..."
            read -p "按回车确认开始，或 Ctrl+C 取消"
            curl -sL "https://raw.githubusercontent.com/spiritLHLS/ecs/main/ecs.sh" | bash
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        *)
            ;;
    esac
}

# 直接运行时进入子菜单
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    while true; do
        show_bench_menu
        read -p "请输入编号: " bchoice
        [[ "$bchoice" == "0" ]] && break
        run_bench "$bchoice"
    done
fi