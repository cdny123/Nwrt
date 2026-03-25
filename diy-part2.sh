#!/bin/bash
#
# diy-part2.sh — feeds install 之后、make defconfig 之前执行
# 策略：只做系统定制和基础优化，不强制选择可能编译失败的第三方插件
# 第三方插件通过 dot.config 选择，编译失败时可逐一排查
#

# 注意：不使用 set -e，防止某个非关键操作失败导致整体中断
set +e

echo "========================================"
echo "  DIY Part 2: 系统个性化配置"
echo "========================================"

# ── 验证工作目录 ─────────────────────────────────────────────────────
if [ ! -f ".config" ]; then
  echo "::error::当前目录没有 .config，脚本必须在 openwrt/ 目录下执行"
  echo "当前目录: $(pwd)"
  exit 1
fi

echo "--- 执行前目标平台 ---"
grep '^CONFIG_TARGET' .config | head -6
echo "---------------------"

# ── 安全写入 config（去重防冲突）────────────────────────────────────
set_config() {
  local key="$1" val="$2"
  # 删除所有同名行，再追加
  grep -v "^${key}[=]" .config > .config.tmp 2>/dev/null && mv .config.tmp .config
  echo "${key}=${val}" >> .config
}

# -------------------------------------------------------
# 网络：管理 IP 192.168.6.1
# -------------------------------------------------------
echo "[*] 设置管理 IP 192.168.6.1..."
if [ -f "package/base-files/files/bin/config_generate" ]; then
  sed -i 's/192\.168\.1\.1/192.168.6.1/g' \
      package/base-files/files/bin/config_generate
fi

mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom-init << 'UCI_END'
#!/bin/sh
uci -q set network.lan.ipaddr="192.168.6.1"
uci -q set system.@system[0].hostname="Openwrt-NIT"
uci commit network
uci commit system
uci -q set ttyd.@ttyd[0].command="/bin/login -f root"
uci commit ttyd 2>/dev/null || true
uci -q set firewall.@defaults[0].flow_offloading="1"
uci commit firewall 2>/dev/null || true
exit 0
UCI_END

# -------------------------------------------------------
# 主机名
# -------------------------------------------------------
echo "[*] 设置主机名 Openwrt-NIT..."
sed -i "s/OpenWrt/Openwrt-NIT/g" \
    package/base-files/files/bin/config_generate 2>/dev/null || true

# -------------------------------------------------------
# Banner
# -------------------------------------------------------
echo "[*] 写入 Banner..."
mkdir -p package/base-files/files/etc
BUILD_DATE="$(TZ=UTC-8 date '+%Y.%m.%d')"
cat > package/base-files/files/etc/banner << BANNER_END
  ___                  _    __    __ _  _____
 / _ \ _ __   ___ _ __ | |  / / /\ \ \|_   _|
| | | | '_ \ / _ \ '_ \| | / /  \ \/ /  | |
| |_| | |_) |  __/ | | | |/ / /\ \  /   | |
 \___/| .__/ \___|_| |_|_/_/ /__\/  /    |_|
      |_|   Openwrt-NIT  ${BUILD_DATE}

     04543473  [$(TZ=UTC-8 date '+%Y.%m.%d')]
     IP: 192.168.6.1  Kernel: 6.6
-----------------------------------------
BANNER_END

# -------------------------------------------------------
# 分区大小
# -------------------------------------------------------
echo "[*] 设置分区大小 kernel=128 rootfs=2048..."
set_config "CONFIG_TARGET_KERNEL_PARTSIZE" "128"
set_config "CONFIG_TARGET_ROOTFS_PARTSIZE" "2048"

# -------------------------------------------------------
# 内核版本
# -------------------------------------------------------
echo "[*] 指定内核 6.6..."
set_config "CONFIG_LINUX_6_6" "y"

# -------------------------------------------------------
# sysctl 千兆优化
# -------------------------------------------------------
echo "[*] 写入 sysctl 网络优化参数..."
mkdir -p package/base-files/files/etc
cat >> package/base-files/files/etc/sysctl.conf << 'SYS_END'

# === 千兆网络优化 ===
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.core.netdev_max_backlog=250000
net.ipv4.tcp_fastopen=3
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.netfilter.nf_conntrack_max=131072
net.netfilter.nf_conntrack_tcp_timeout_established=7440
net.ipv4.ip_forward=1
vm.swappiness=10
SYS_END

# ---------- 1. 添加 Argon 主题和配置插件 ----------
# 克隆主题（使用 master 分支，适合官方 OpenWrt 24.10+ / main）
git clone https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
# 克隆主题配置插件（可选，但强烈推荐）
git clone https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config

# ---------- 2. 设置 Argon 为默认主题 ----------
# 创建 default-settings 包，确保 Argon 在首次启动时被设为默认主题
DEFAULT_SETTINGS_DIR="package/default-settings/files"
mkdir -p "$DEFAULT_SETTINGS_DIR"

cat > "$DEFAULT_SETTINGS_DIR/zzz-default-settings" << 'EOF'
#!/bin/sh
# 设置默认主题为 Argon
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci
exit 0
EOF

chmod +x "$DEFAULT_SETTINGS_DIR/zzz-default-settings"

# 在 .config 中启用 default-settings 包（如果尚未启用）
# 注意：如果用户之后运行 make menuconfig，可能需要手动确认
if ! grep -q "CONFIG_PACKAGE_default-settings=y" .config 2>/dev/null; then
    echo "CONFIG_PACKAGE_default-settings=y" >> .config
fi

# -------------------------------------------------------
# 修正第三方包版本号（APK 不允许连字符）
# 用单线程串行处理，避免 xargs 并行时 set -e 误中断
# -------------------------------------------------------
echo "[*] 修正包版本号..."
find package/ feeds/ -maxdepth 5 -name "Makefile" \
     -not -path "*/.git/*" 2>/dev/null | while read -r mk; do
  ver=$(grep -oP '^PKG_VERSION:=\K.+' "$mk" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$ver" ] && echo "$ver" | grep -q '-'; then
    fixed=$(echo "$ver" | tr '-' '.')
    sed -i "s|^PKG_VERSION:=.*|PKG_VERSION:=${fixed}|" "$mk"
    sed -i "s|^PKG_RELEASE:=.*|PKG_RELEASE:=1|" "$mk"
    echo "  fixed: $(basename "$(dirname "$mk")") ${ver} -> ${fixed}"
  fi
done
echo "[✓] 版本号修正完成"

# -------------------------------------------------------
# 最终检查
# -------------------------------------------------------
echo ""
echo "--- 执行后目标平台 ---"
grep '^CONFIG_TARGET' .config | head -6
echo "---------------------"
echo "[✓] DIY Part 2 完成"
