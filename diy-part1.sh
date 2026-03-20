#!/bin/bash
#
# diy-part1.sh — 在 feeds update 之前执行
# 适配 OpenWrt 25.x APK 打包规范，自动修正所有插件版本号
#

set -e
echo "========================================"
echo "  DIY Part 1: 添加自定义插件和 Feeds"
echo "========================================"

# -----------------------------------------------
# 工具函数：修正 Makefile 版本号
# OpenWrt 25.x 使用 APK 打包，版本号规则：
#   - 只允许数字和小数点，如 1.2.3
#   - 不允许连字符(-)，如 0.8.16-1 → 非法
# 修正方式：将 PKG_VERSION + PKG_RELEASE 合并为 X.Y.Z.R
# -----------------------------------------------
fix_pkg_version() {
  local dir="$1"
  local mk="$dir/Makefile"
  [ -f "$mk" ] || return 0

  local ver rel new_ver
  ver=$(grep -oP '^PKG_VERSION:=\K.+' "$mk" 2>/dev/null | head -1 | tr -d '[:space:]')
  rel=$(grep -oP '^PKG_RELEASE:=\K.+' "$mk" 2>/dev/null | head -1 | tr -d '[:space:]')

  # 如果版本号包含连字符，说明需要修正
  if echo "$ver" | grep -q '-'; then
    # 把版本号里的 - 替换为 .
    new_ver=$(echo "$ver" | tr '-' '.')
    sed -i "s|^PKG_VERSION:=.*|PKG_VERSION:=${new_ver}|" "$mk"
    echo "  [fix] $(basename $dir): version ${ver} → ${new_ver}"
  fi

  # PKG_RELEASE 如果存在且不为纯数字，将其清零
  if [ -n "$rel" ] && ! echo "$rel" | grep -qP '^\d+$'; then
    sed -i "s|^PKG_RELEASE:=.*|PKG_RELEASE:=1|" "$mk"
    echo "  [fix] $(basename $dir): release '${rel}' → 1"
  fi
}

# -----------------------------------------------
# 克隆插件
# -----------------------------------------------

echo "[*] 克隆 luci-theme-kucat 主题..."
git clone --depth=1 https://github.com/sirpdboy/luci-theme-kucat.git package/luci-theme-kucat
fix_pkg_version package/luci-theme-kucat

echo "[*] 克隆 luci-app-quickstart..."
git clone --depth=1 https://github.com/lq-wq/luci-app-quickstart.git package/luci-app-quickstart
fix_pkg_version package/luci-app-quickstart

echo "[*] 克隆 luci-app-lucky..."
git clone --depth=1 https://github.com/sirpdboy/luci-app-lucky.git package/lucky
fix_pkg_version package/lucky

echo "[*] 克隆 luci-app-partexp 分区扩容..."
git clone --depth=1 https://github.com/sirpdboy/luci-app-partexp.git package/luci-app-partexp
fix_pkg_version package/luci-app-partexp

echo "[*] 克隆 OpenAppFilter 应用过滤..."
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter
# OpenAppFilter 包含多个子包，逐一修正
for d in package/OpenAppFilter/*/; do
  [ -f "$d/Makefile" ] && fix_pkg_version "$d"
done
fix_pkg_version package/OpenAppFilter

echo "[*] 克隆 luci-app-adguardhome..."
git clone --depth=1 -b master https://github.com/rufengsuixing/luci-app-adguardhome.git package/luci-app-adguardhome
fix_pkg_version package/luci-app-adguardhome

# -----------------------------------------------
# 预下载 AdGuardHome 核心（amd64）
# 构建时直接打包进固件，无需首次开机再下载
# -----------------------------------------------
AGH_VERSION="v0.107.55"
AGH_CORE_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${AGH_VERSION}/AdGuardHome_linux_amd64.tar.gz"
AGH_CORE_DIR="package/luci-app-adguardhome/root/usr/bin"
mkdir -p "$AGH_CORE_DIR"
echo "[*] 下载 AdGuardHome 核心 ${AGH_VERSION}..."
if wget -qO /tmp/adguardhome.tar.gz "$AGH_CORE_URL"; then
  tar -xzf /tmp/adguardhome.tar.gz -C /tmp/
  cp /tmp/AdGuardHome/AdGuardHome "$AGH_CORE_DIR/AdGuardHome"
  chmod +x "$AGH_CORE_DIR/AdGuardHome"
  echo "[✓] AdGuardHome 核心已就绪"
else
  echo "[!] AdGuardHome 核心下载失败，将在路由器运行时自动下载"
fi

echo ""
echo "[✓] DIY Part 1 完成"
