#!/bin/bash

# [大锤sand-box] 配置组装与热加载 (Re-assembler & Hot Reload)
# 整合基础配置与动态 WARP 池，发送 SIGHUP

source ./core.sh

BASE_CONF="/etc/hammer-sb/base_config.json"
WARP_POOL_CONF="/etc/hammer-sb/warp_pool.json"
FINAL_CONF="/etc/hammer-sb/config.json"

assemble_and_reload() {
    log_info "正在重新组装配置文件..."
    
    # 使用 jq 将池子节点注入到基础配置的 outbounds 中
    # 我们假设 base_config.json 中已经定义了 selector 引用了这些 tag
    jq --slurpfile pool "$WARP_POOL_CONF" \
       '.outbounds += $pool[0]' "$BASE_CONF" > "$FINAL_CONF"
    
    if [[ $? -eq 0 ]]; then
        log_info "配置文件组装成功，正在启动/重载服务..."
        if systemctl is-active --quiet hammer-sb 2>/dev/null; then
            systemctl reload hammer-sb
        else
            systemctl start hammer-sb
        fi
        log_info "Sing-Box 已启动/重载。"
    else
        log_error "配置文件组装失败，请检查 JSON 格式。"
    fi
}

# 设置定时任务 (Set Cron Job)
# 每 M 分钟执行一次 rotate_one_ip
setup_cron() {
    local minutes=$1
    log_info "正在设置每 $minutes 分钟自动轮换一个 WARP IP..."
    (crontab -l 2>/dev/null | grep -v "warp_rotate.sh"; echo "*/$minutes * * * * $(pwd)/warp_rotate.sh >> /var/log/hammer-sb-rotate.log 2>&1") | crontab -
}

# 直接执行时自动组装并重载
case "$1" in
    --cron)
        shift
        setup_cron "$1"
        ;;
    *)
        assemble_and_reload
        ;;
esac
