#!/bin/bash
# Модуль 00: Базовая подготовка системы CentOS 9

set -e

log() { echo -e "\033[0;36m[00-base]\033[0m $1"; }

log "🔄 Обновление системы..."
dnf update -y

log "📦 Установка базовых пакетов..."
dnf install -y epel-release dnf-plugins-core git curl wget bind-utils \
    iputils ipset iptables iproute jq cronie make gcc pkgconfig tcpdump idn2 \
    nano vim-enhanced htop dnsmasq
dnf config-manager --set-enabled crb

log "🌐 Настройка DNS..."
chattr -i /etc/resolv.conf 2>/dev/null || true
cat > /etc/resolv.conf << 'EOF'
nameserver 9.9.9.10
nameserver 1.1.1.1
nameserver 76.76.2.0
nameserver 194.169.169.169
nameserver 64.6.64.6
nameserver 64.6.65.6
nameserver 101.226.4.6
nameserver 193.58.251.251
options timeout:2 attempts:2 rotate inet4
EOF
chattr +i /etc/resolv.conf
sed -i 's/^hosts:.*$/hosts:      files dns/' /etc/nsswitch.conf
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true

log "📁 Создание структуры директорий..."
mkdir -p "$AMNEZIA_DIR"/{clients,server-clients,server-clients-full,lists,logs}
mkdir -p /etc/amnezia/amneziawg
mkdir -p /etc/dnsmasq.d
chown -R "$CURRENT_USER:$CURRENT_USER" "$AMNEZIA_DIR" 2>/dev/null || true

log "⚙️  Настройка системных параметров..."
cat > /etc/sysctl.d/99-ipforward.conf << 'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=2
net.ipv4.conf.default.rp_filter=2
EOF
sysctl -p /etc/sysctl.d/99-ipforward.conf

log "✅ Базовая подготовка завершена (dnsmasq установлен, massdns не требуется)"