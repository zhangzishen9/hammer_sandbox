#!/bin/bash

# [大锤sand-box] 动态 IP 旋转脚本 (WARP IP Rotator)
# 逻辑: 选定池中的节点 -> 重新注册 -> 更新池文件 -> 组装并重载

source ./core.sh
source ./warp_pool.sh

BASE_DIR="/etc/hammer-sb"
WARP_POOL_CONF="$BASE_DIR/warp_pool.json"

log_info "------------------------------------------"
log_info "启动定时任务: WARP IP 轮换节点刷新"

# 1. 检查池子文件是否存在
if [[ ! -f "$WARP_POOL_CONF" ]]; then
    log_error "未发现池子配置文件，请先执行安装流程。"
    exit 1
fi

# 2. 随机决定要刷新的节点索引 (1 到 N)
pool_size=$(jq '. | length' "$WARP_POOL_CONF")
target_idx=$(shuf -i 1-$pool_size -n 1)
log_info "随机选择池子位 [$target_idx] 进行重新注册..."

# 3. 重新获取新的账号信息 (物理切 IP)
acc_info=$(register_warp_account)
priv=$(echo $acc_info | cut -d',' -f1)
ip6=$(echo $acc_info | cut -d',' -f2)
res=$(echo $acc_info | cut -d',' -f3)

# 4. 使用 jq 更新池子文件中的对应节点
jq ".[$((target_idx-1))].private_key = \"$priv\" | \
    .[$((target_idx-1))].local_address = [\"172.16.0.2/32\", \"$ip6/128\"] | \
    .[$((target_idx-1))].reserved = $res" "$WARP_POOL_CONF" > "$WARP_POOL_CONF.tmp"

mv "$WARP_POOL_CONF.tmp" "$WARP_POOL_CONF"

# 5. 触发重组与重载
bash ./re-assemble.sh
log_info "节点 [$target_idx] 刷新完成，新 IP 已生效。"
log_info "------------------------------------------"
