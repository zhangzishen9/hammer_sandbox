#!/bin/bash
# ==============================================================================
# 国际主流网站互联测试 (pingtest)
# ==============================================================================

if command -v pt &>/dev/null; then
    pt -tm web "$@"
    exit 0
fi

echo "正在准备 pingtest (网络连通性测试工具)..."
curl -sL https://raw.githubusercontent.com/oneclickvirt/pingtest/main/pt_install.sh -sSf | bash || \
curl -sL https://cdn.spiritlhl.net/https://raw.githubusercontent.com/oneclickvirt/pingtest/main/pt_install.sh -sSf | bash

if command -v pt &>/dev/null; then
    pt -tm web "$@"
elif [ -f "./pt" ]; then
    ./pt -tm web "$@"
else
    echo "安装 pingtest 失败，请检查网络。"
fi
