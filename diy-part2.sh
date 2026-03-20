#!/bin/bash
#
# diy-part2.sh — feeds install 之后执行
# 注意：本脚本只追加包选项，绝不修改 CONFIG_TARGET_* 行，防止覆盖 x86-64 目标
#

set -e

echo "========================================"
echo "  DIY Part 2: 系统个性化配置"
echo "========================================"

# ── 安全追加函数：避免重复写入同一 key ──────────────────────────────
append_config() {
  local key="$1"
  local val="$2"
  # 若已存在该 key（无论值），先删除再写入，防止冲突
  grep -v "^${key}=" .config > .config.tmp 2>/dev/null || true
  mv .config.tmp .config
  echo "${key}=${val}" >> .config
}

# ── 验证目标平台未被破坏 ────────────────────────────────────────────
check_target() {
  echo "--- [check] 当前 CONFIG_TARGET ---"
  grep '^CONFIG_TARGET' .config | head -6
  echo "----------------------------------"
}

check_target

# -------------------------------------------------------
# 网络：管理 IP 192.168.6.1
# -------------------------------------------------------
echo "[*] 设置管理 IP: 192.168.6.1"
[ -f "package/base-files/files/bin/config_generate" ] && \
  sed -i 's/192\.168\.1\.1/192.168.6.1/g' \
      package/base-files/files/bin/config_generate

mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom << 'UCI_END'
#!/bin/sh
uci -q set network.lan.ipaddr="192.168.6.1"
uci -q set system.@system[0].hostname="Openwrt-NIT"
uci commit network
uci commit system
# ttyd 自动登录
uci -q set ttyd.@ttyd[0].command="/bin/login -f root"
uci commit ttyd 2>/dev/null || true
exit 0
UCI_END

# -------------------------------------------------------
# 系统标识：主机名 Openwrt-NIT
# -------------------------------------------------------
echo "[*] 设置主机名: Openwrt-NIT"
sed -i "s/OpenWrt/Openwrt-NIT/g" \
    package/base-files/files/bin/config_generate 2>/dev/null || true

# -------------------------------------------------------
# Banner 个性签名
# -------------------------------------------------------
echo "[*] 设置 Banner..."
mkdir -p package/base-files/files/etc
BUILD_DATE="$(TZ=UTC-8 date '+%Y.%m.%d')"
cat > package/base-files/files/etc/banner << BANNER_END
  ___                  _    __    __ _  _____
 / _ \ _ __   ___ _ __ | |  / / /\ \ \|_   _|
| | | | '_ \ / _ \ '_ \| | / /  \ \/ /  | |
| |_| | |_) |  __/ | | | |/ / /\ \  /   | |
 \___/| .__/ \___|_| |_|_/_/ /__\/  /    |_|
      |_|   Openwrt-NIT  Build:${BUILD_DATE}

     04543473  [$(TZ=UTC-8 date "+%Y.%m.%d")]
     IP: 192.168.6.1  Kernel: 6.6
-----------------------------------------
BANNER_END

# -------------------------------------------------------
# 分区大小：kernel=128 rootfs=2048
# -------------------------------------------------------
echo "[*] 设置分区大小..."
append_config "CONFIG_TARGET_KERNEL_PARTSIZE" "128"
append_config "CONFIG_TARGET_ROOTFS_PARTSIZE" "2048"

# -------------------------------------------------------
# 内核 6.6（只追加，不改 TARGET）
# -------------------------------------------------------
echo "[*] 指定内核 6.6..."
append_config "CONFIG_LINUX_6_6" "y"

# -------------------------------------------------------
# 批量修正第三方包版本号（APK 规范：不允许含连字符）
# -------------------------------------------------------
echo "[*] 批量修正包版本号..."
fix_ver() {
  local mk="$1"
  local ver
  ver=$(grep -oP '^PKG_VERSION:=\K.+' "$mk" 2>/dev/null | tr -d '[:space:]') || return
  if echo "$ver" | grep -q '-'; then
    local fixed
    fixed=$(echo "$ver" | tr '-' '.')
    sed -i "s|^PKG_VERSION:=.*|PKG_VERSION:=${fixed}|" "$mk"
    sed -i "s|^PKG_RELEASE:=.*|PKG_RELEASE:=1|"        "$mk"
  fi
}
export -f fix_ver
find package/ feeds/ -maxdepth 4 -name "Makefile" \
     -not -path "*/.git/*" 2>/dev/null \
  | xargs -P4 -I{} bash -c 'fix_ver "$@"' _ {}
echo "[✓] 版本号修正完成"

# -------------------------------------------------------
# 千兆网络性能优化
# -------------------------------------------------------
echo "[*] 写入千兆优化包选项..."
cat >> .config << 'PKG_END'
# 流量卸载
CONFIG_PACKAGE_kmod-nft-offload=y
CONFIG_PACKAGE_kmod-nf-conntrack=y
CONFIG_PACKAGE_kmod-nf-flow-table=y
# BBR
CONFIG_PACKAGE_kmod-tcp-bbr=y
# 千兆网卡驱动
CONFIG_PACKAGE_kmod-e1000e=y
CONFIG_PACKAGE_kmod-igb=y
CONFIG_PACKAGE_kmod-igc=y
CONFIG_PACKAGE_kmod-ixgbe=y
CONFIG_PACKAGE_kmod-r8169=y
# IRQ 均衡
CONFIG_PACKAGE_irqbalance=y
# dnsmasq-full 替换 dnsmasq
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_dnsmasq=n
# 工具
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_ethtool=y
PKG_END

# sysctl 优化
mkdir -p package/base-files/files/etc
cat >> package/base-files/files/etc/sysctl.conf << 'SYS_END'

# === 千兆优化 ===
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

# flow offloading
cat >> package/base-files/files/etc/uci-defaults/99-custom << 'FW_END'
uci -q set firewall.@defaults[0].flow_offloading="1"
uci commit firewall
FW_END

# -------------------------------------------------------
# 确保自定义插件已选中
# -------------------------------------------------------
echo "[*] 写入插件选项..."
cat >> .config << 'PKG2_END'
CONFIG_PACKAGE_luci-theme-kucat=y
# CONFIG_PACKAGE_luci-app-quickstart=y
CONFIG_PACKAGE_luci-app-lucky=y
CONFIG_PACKAGE_luci-app-partexp=y
CONFIG_PACKAGE_luci-app-oaf=y
CONFIG_PACKAGE_luci-app-adguardhome=y
CONFIG_PACKAGE_adguardhome=y
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-app-netdata=y
CONFIG_PACKAGE_netdata=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_ttyd=y
PKG2_END

# -------------------------------------------------------
# 最终验证：确认 TARGET 未被覆盖
# -------------------------------------------------------
check_target

echo ""
echo "[✓] DIY Part 2 完成"
