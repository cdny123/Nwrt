#!/bin/bash
#
# diy-part1.sh — 在 feeds update 之前执行
# 用途：克隆第三方插件到 package 目录，配置自定义 feeds
#

echo "========================================"
echo "  DIY Part 1: 添加自定义插件和 Feeds"
echo "========================================"

# -----------------------------------------------
# 添加 APP 插件（直接克隆到 package 目录）
# -----------------------------------------------

echo "[*] 克隆 luci-theme-kucat 主题..."
git clone --depth=1 https://github.com/sirpdboy/luci-theme-kucat.git package/luci-theme-kucat

echo "[*] 克隆 luci-app-quickstart 快速启动..."
git clone --depth=1 https://github.com/lq-wq/luci-app-quickstart.git package/luci-app-quickstart

echo "[*] 克隆 luci-app-lucky..."
git clone --depth=1 https://github.com/sirpdboy/luci-app-lucky.git package/lucky

echo "[*] 克隆 luci-app-partexp 分区扩容..."
git clone --depth=1 https://github.com/sirpdboy/luci-app-partexp.git package/luci-app-partexp

echo "[*] 克隆 OpenAppFilter 应用过滤..."
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter

# -----------------------------------------------
# 添加 AdGuardHome 插件和核心
# 编译固件时自动集成 AdGuardHome 及其核心二进制
# -----------------------------------------------

echo "[*] 克隆 luci-app-adguardhome..."
git clone --depth=1 -b master https://github.com/rufengsuixing/luci-app-adguardhome.git package/luci-app-adguardhome

# 预下载 AdGuardHome 核心（amd64）
AGH_VERSION="v0.107.55"
AGH_CORE_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${AGH_VERSION}/AdGuardHome_linux_amd64.tar.gz"
AGH_CORE_DIR="package/luci-app-adguardhome/root/usr/bin"
mkdir -p "$AGH_CORE_DIR"
echo "[*] 下载 AdGuardHome 核心 ${AGH_VERSION}..."
wget -qO /tmp/adguardhome.tar.gz "$AGH_CORE_URL" && \
  tar -xzf /tmp/adguardhome.tar.gz -C /tmp/ && \
  cp /tmp/AdGuardHome/AdGuardHome "$AGH_CORE_DIR/AdGuardHome" && \
  chmod +x "$AGH_CORE_DIR/AdGuardHome" && \
  echo "[*] AdGuardHome 核心已就绪: $AGH_CORE_DIR/AdGuardHome" || \
  echo "[!] AdGuardHome 核心下载失败，将在运行时自动下载"

echo ""
echo "[✓] DIY Part 1 完成"
