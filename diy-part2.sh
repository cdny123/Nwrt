#!/bin/bash
#
# diy-part2.sh — 在 feeds install 之后、make defconfig 之前执行
# 用途：自定义系统配置、网络、主机名、内核参数等
#

echo "========================================"
echo "  DIY Part 2: 系统个性化配置"
echo "========================================"

# -----------------------------------------------
# 网络配置：设置管理 IP 为 192.168.6.1
# -----------------------------------------------
echo "[*] 设置默认管理 IP: 192.168.6.1"
[ -f "package/base-files/files/bin/config_generate" ] && \
sed -i 's/192\.168\.1\.1/192.168.6.1/g' package/base-files/files/bin/config_generate

# 也修改网络 UCI 默认值（适配不同版本）
[ -d "package/base-files/files/etc/uci-defaults" ] || mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom-network << 'EOF'
#!/bin/sh
uci -q set network.lan.ipaddr="192.168.6.1"
uci commit network
exit 0
EOF

# -----------------------------------------------
# 系统标识：设置主机名为 Openwrt-NIT
# -----------------------------------------------
echo "[*] 设置主机名: Openwrt-NIT"
sed -i "s/OpenWrt/Openwrt-NIT/g" package/base-files/files/bin/config_generate 2>/dev/null || true

cat >> package/base-files/files/etc/uci-defaults/99-custom-network << 'EOF'
uci -q set system.@system[0].hostname="Openwrt-NIT"
uci commit system
EOF

# -----------------------------------------------
# ttyd 自动登录配置
# -----------------------------------------------
echo "[*] 配置 ttyd 自动登录..."
[ -d "package/feeds/packages/ttyd" ] && {
  mkdir -p package/base-files/files/etc/init.d
  cat > package/base-files/files/etc/uci-defaults/99-ttyd-autologin << 'EOF'
#!/bin/sh
uci -q set ttyd.@ttyd[0].command="/bin/login -f root"
uci commit ttyd
exit 0
EOF
}

# -----------------------------------------------
# 内核和系统分区大小：kernel=128MB, rootfs=2048MB
# -----------------------------------------------
echo "[*] 设置分区大小: kernel=128MB rootfs=2048MB"

# x86 grub 分区配置
GRUB_CFG="target/linux/x86/image/grub.cfg"
[ -f "$GRUB_CFG" ] && {
  sed -i 's/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=128/' .config 2>/dev/null || true
  sed -i 's/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=2048/' .config 2>/dev/null || true
}

# 写入 .config（defconfig 后也可覆盖）
cat >> .config << 'EOF'
CONFIG_TARGET_KERNEL_PARTSIZE=128
CONFIG_TARGET_ROOTFS_PARTSIZE=2048
EOF

# -----------------------------------------------
# 个性签名（Banner）
# 格式：04543473 + 当前日期 [YYYY.MM.DD]
# -----------------------------------------------
echo "[*] 设置个性签名 Banner..."
mkdir -p package/base-files/files/etc
BUILD_DATE="$(TZ=UTC-8 date '+%Y.%m.%d')"
cat > package/base-files/files/etc/banner << EOF
  ___                  _    __    __ _  _____
 / _ \ _ __   ___ _ __ | |  / / /\ \ \|_   _|
| | | | '_ \ / _ \ '_ \| | / /  \ \/ /  | |
| |_| | |_) |  __/ | | | |/ / /\ \  /   | |
 \___/| .__/ \___|_| |_|_/_/ /__\/  /    |_|
      |_|   Openwrt-NIT  ${BUILD_DATE}

     By 04543473  [$(TZ=UTC-8 date "+%Y.%m.%d")]
     IP: 192.168.6.1  Kernel: 6.6
----------------------------------------
EOF

# -----------------------------------------------
# 更换固件内核为 6.6
# -----------------------------------------------
echo "[*] 指定内核版本为 6.6..."
cat >> .config << 'EOF'
CONFIG_LINUX_6_6=y
EOF

# -----------------------------------------------
# 万兆/千兆网络性能优化 (1000Mbps 跑满优化)
# -----------------------------------------------
echo "[*] 应用千兆网络性能优化..."

cat >> .config << 'EOF'
# ====== 千兆网络性能优化 ======
# 软件流量卸载（BBR + Flow Offload）
CONFIG_PACKAGE_kmod-nft-offload=y
CONFIG_PACKAGE_kmod-nf-conntrack=y
CONFIG_PACKAGE_kmod-nf-flow-table=y

# 硬件流量卸载（需要网卡支持）
CONFIG_PACKAGE_kmod-nft-offload=y

# BBR 拥塞控制
CONFIG_PACKAGE_kmod-tcp-bbr=y

# 多队列网卡支持
CONFIG_PACKAGE_kmod-bnx2=y
CONFIG_PACKAGE_kmod-e1000e=y
CONFIG_PACKAGE_kmod-igb=y
CONFIG_PACKAGE_kmod-ixgbe=y
CONFIG_PACKAGE_kmod-r8169=y

# IRQ 亲和性 / SMP 调度
CONFIG_PACKAGE_irqbalance=y

# DNS 加速
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_dnsmasq=n

# 网络工具
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_ethtool=y
EOF

# 写入 sysctl 性能优化参数
mkdir -p package/base-files/files/etc
cat >> package/base-files/files/etc/sysctl.conf << 'EOF'

# ====== 千兆网络优化 by diy-part2.sh ======
# TCP 缓冲区
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.core.netdev_max_backlog=250000
net.ipv4.tcp_fastopen=3

# BBR 拥塞控制
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# 连接追踪优化
net.netfilter.nf_conntrack_max=131072
net.netfilter.nf_conntrack_tcp_timeout_established=7440
net.netfilter.nf_conntrack_udp_timeout=60
net.netfilter.nf_conntrack_udp_timeout_stream=120

# 转发与 ARP
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=1

# 减少内存碎片
vm.swappiness=10
EOF

# 开启 flow offloading（UCI）
cat >> package/base-files/files/etc/uci-defaults/99-custom-network << 'EOF'
# 开启软件流量卸载
uci -q set firewall.@defaults[0].flow_offloading="1"
uci commit firewall
EOF

# -----------------------------------------------
# AdGuardHome 插件确保选中
# -----------------------------------------------
echo "[*] 确保 AdGuardHome 插件已选中..."
cat >> .config << 'EOF'
CONFIG_PACKAGE_luci-app-adguardhome=y
CONFIG_PACKAGE_adguardhome=y
EOF

# -----------------------------------------------
# 其他推荐插件选中
# -----------------------------------------------
cat >> .config << 'EOF'
# 基础功能
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_luci-app-opkg=y

# 自定义插件
CONFIG_PACKAGE_luci-theme-kucat=y
# CONFIG_PACKAGE_luci-app-quickstart=y
CONFIG_PACKAGE_luci-app-lucky=y
CONFIG_PACKAGE_luci-app-partexp=y
CONFIG_PACKAGE_luci-app-oaf=y
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-app-netdata=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_ttyd=y
EOF

echo ""
echo "[✓] DIY Part 2 完成"
