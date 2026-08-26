#!/bin/bash

# [大锤sand-box] VPS 体检中心 (Benchmark & Check Center)
# 内置独立体检模块，支持本地极速执行与远端仓库双重保障

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$SCRIPT_DIR/bench"
REPO_RAW_URL="https://raw.githubusercontent.com/zhangzishen9/hammer_sandbox/main/hammer-sandbox/bench"

if [ -f "$SCRIPT_DIR/core.sh" ]; then
    source "$SCRIPT_DIR/core.sh"
else
    log_info() { echo -e "\033[32m[INFO]\033[0m $*"; }
    log_warn() { echo -e "\033[33m[WARN]\033[0m $*"; }
    log_error() { echo -e "\033[31m[ERROR]\033[0m $*"; }
fi

run_local_or_remote_bench() {
    local script_name=$1
    shift
    local local_script="$BENCH_DIR/$script_name"
    
    if [ -f "$local_script" ]; then
        chmod +x "$local_script"
        bash "$local_script" "$@"
    else
        log_warn "未检测到本地 $script_name，正在从主仓库同步..."
        mkdir -p "$BENCH_DIR"
        if curl -sL "$REPO_RAW_URL/$script_name" -o "$local_script" && [ -s "$local_script" ]; then
            chmod +x "$local_script"
            bash "$local_script" "$@"
        else
            log_error "从仓库下载 $script_name 失败，请检查网络连接。"
        fi
    fi
}

show_bench_menu() {
    clear
    echo -e "${blue}========================================${plain}"
    echo -e "       ${blue}大锤 VPS 体检中心${plain}           "
    echo -e "${blue}========================================${plain}"
    echo -e "--- 网络篇 ---"
    echo -e " 1. 三网回程路由 (电信/联通/移动 traceroute)"
    echo -e " 2. 三网去程路由 (广州/上海/北京→本地 VPS)"
    echo -e " 3. 国际主流网站互联测试 (CDN/网站延迟)"
    echo -e ""
    echo -e "--- IP 质量篇 ---"
    echo -e " 4. IP 质量与风控检测 (46项: 欺诈值/黑名单/原生度)"
    echo -e " 5. 流媒体与AI解锁检测 (Netflix/Disney/YouTube/ChatGPT)"
    echo -e ""
    echo -e "--- 性能篇 ---"
    echo -e " 6. 基础跑分 (CPU/内存/磁盘IO/网速速览)"
    echo -e " 7. YABS 跑分 (fio磁盘/Geekbench 综合跑分)"
    echo -e ""
    echo -e "--- 一键全测 ---"
    echo -e " 8. 融合怪全量检测 (硬件/网络/解锁全套测评)"
    echo -e ""
    echo -e " 0. 返回主菜单"
    echo -e "${blue}========================================${plain}"
    echo -e "所有脚本已本地内置，秒级启动且不受外部链接失效影响。"
    echo -e "${blue}========================================${plain}"
}

run_bench() {
    local choice=$1
    case $choice in
        1)
            log_info "正在运行: 三网回程路由检测..."
            echo ""
            run_local_or_remote_bench "backtrace.sh"
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        2)
            log_info "正在运行: 三网去程路由检测..."
            echo ""
            run_local_or_remote_bench "route.sh"
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        3)
            log_info "正在运行: 国际主流网站互联测试..."
            echo ""
            run_local_or_remote_bench "pingtest.sh"
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        4)
            log_info "正在运行: IP 质量与风控检测 (IPQuality)..."
            echo ""
            run_local_or_remote_bench "ipcheck.sh"
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        5)
            log_info "正在运行: 流媒体与 AI 解锁检测..."
            echo ""
            run_local_or_remote_bench "media_check.sh"
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        6)
            log_info "正在运行: 基础跑分 (CPU/IO/带宽)..."
            echo ""
            run_local_or_remote_bench "bench.sh"
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        7)
            log_info "正在运行: YABS 跑分 (fio磁盘/Geekbench)..."
            echo ""
            run_local_or_remote_bench "yabs.sh"
            echo ""
            read -p "测试完毕，按回车键返回..."
            ;;
        8)
            log_info "正在运行: 融合怪全量检测..."
            echo ""
            log_warn "此检测耗时约 5-15 分钟，请耐心等待..."
            read -p "按回车确认开始，或 Ctrl+C 取消"
            run_local_or_remote_bench "ecs.sh"
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