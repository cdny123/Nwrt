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

# -----------------------------------------------
# luci-app-quickstart 版本号修复
# openwrt-25.x 使用 APK 打包，版本号不能包含连字符(-)
# 原版本 0.8.16-1 中的 "-1" 会导致 "package version is invalid"
# 解决方案：克隆后修改 Makefile，将 PKG_RELEASE 合并进 PKG_VERSION
# -----------------------------------------------
echo "[*] 克隆 luci-app-quickstart（含版本号补丁）..."
git clone --depth=1 https://github.com/lq-wq/luci-app-quickstart.git package/luci-app-quickstart

# 修正版本号格式：将 PKG_VERSION + PKG_RELEASE 合并为单一无连字符版本
# APK 规范要求版本号格式为 X.Y.Z，不允许带 -release 后缀
MK="package/luci-app-quickstart/Makefile"
if [ -f "$MK" ]; then
  # 读取原始版本和 release
  PKG_VER=$(grep -oP 'PKG_VERSION:=\K[^\s]+' "$MK" | head -1)
  PKG_REL=$(grep -oP 'PKG_RELEASE:=\K[^\s]+' "$MK" | head -1)
  if [ -n "$PKG_VER" ] && [ -n "$PKG_REL" ]; then
    # 合并为 X.Y.Z.R 格式（全数字点分隔，APK 合法）
    NEW_VER="${PKG_VER}.${PKG_REL}"
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=${NEW_VER}/" "$MK"
    sed -i "s/PKG_RELEASE:=.*/PKG_RELEASE:=0/" "$MK"
    echo "[*] quickstart 版本号已修正: ${PKG_VER}-${PKG_REL} → ${NEW_VER}"
  else
    # 兜底：直接写死一个合法版本
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=0.8.16/" "$MK"
    sed -i "s/PKG_RELEASE:=.*/PKG_RELEASE:=0/" "$MK"
    echo "[!] quickstart 版本号兜底修正为 0.8.16"
  fi
fi

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
