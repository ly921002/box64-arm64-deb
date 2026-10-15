#!/bin/bash
set -e

echo "==== 安装 Box64 Debian 包 ===="

if [ -f "./box64-deb.deb" ]; then
    dpkg -i ./box64-deb.deb || true
else
    echo "未找到 box64-deb.deb，请放在脚本同目录"
    exit 1
fi


echo "==== 启用 amd64 架构 ===="

dpkg --add-architecture amd64


echo "==== 更新 apt 源 ===="

apt update


echo "==== 安装 x86_64 运行库 ===="

apt install -y \
    libc6:amd64 \
    libstdc++6:amd64 \
    libgcc-s1:amd64 \
    libcurl4:amd64 \
    libssl3:amd64 \
    zlib1g:amd64


echo "==== 修复依赖 ===="

apt -f install -y


echo "==== 检查安装结果 ===="

echo "Box64:"
box64 -v || true

echo ""
echo "x86_64 libraries:"
ls -l \
/usr/lib/x86_64-linux-gnu/libstdc++.so.6 \
/usr/lib/x86_64-linux-gnu/libc.so.6 \
2>/dev/null || true


echo ""
echo "==== 完成 ===="