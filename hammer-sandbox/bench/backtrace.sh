#!/bin/bash
# ==============================================================================
# 三网回程路由检测 (Backtrace)
# ==============================================================================

arch=$(uname -m)
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR" || exit 1

if [ "$arch" = "x86_64" ] || [ "$arch" = "amd64" ]; then
    DOWNLOAD_URL="https://github.com/zhanghanyun/backtrace/releases/latest/download/backtrace-linux-amd64.tar.gz"
elif [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
    DOWNLOAD_URL="https://github.com/zhanghanyun/backtrace/releases/latest/download/backtrace-linux-arm64.tar.gz"
else
    echo "不支持的 CPU 架构: $arch"
    rm -rf "$TMP_DIR"
    exit 1
fi

echo "正在下载 backtrace ($arch)..."
if curl -sL "$DOWNLOAD_URL" -o backtrace.tar.gz || wget -qO backtrace.tar.gz "$DOWNLOAD_URL"; then
    tar -zxf backtrace.tar.gz
    chmod +x backtrace
    ./backtrace
else
    echo "下载 backtrace 失败，尝试备用链路..."
    curl -sL https://raw.githubusercontent.com/oneclickvirt/backtrace/main/backtrace_install.sh -sSf | bash
fi

rm -rf "$TMP_DIR"
