#!/bin/bash
# ==============================================================================
# 三网去程路由检测 (nt3 / NextTrace)
# ==============================================================================

if command -v nt3 &>/dev/null; then
    nt3 "$@"
    exit 0
fi

echo "正在准备 nt3 (三网路由测试工具)..."
curl -sL https://raw.githubusercontent.com/oneclickvirt/nt3/main/nt3_install.sh -sSf | bash || \
curl -sL https://cdn.spiritlhl.net/https://raw.githubusercontent.com/oneclickvirt/nt3/main/nt3_install.sh -sSf | bash

if command -v nt3 &>/dev/null; then
    nt3 "$@"
elif [ -f "./nt3" ]; then
    ./nt3 "$@"
else
    echo "尝试使用 NextTrace 备用测试..."
    bash <(curl -sL nxtrace.org/nt)
fi
