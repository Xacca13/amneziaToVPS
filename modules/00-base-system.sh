#!/bin/bash
# Модуль 00: Базовая подготовка системы CentOS 9

set -e

log() { echo -e "\033[0;36m[00-base]\033[0m $1"; }

log "🔄 Обновление системы..."
dnf update -y

log "📦 Установка базовых пакетов..."
dnf install -y epel-release dnf-plugins-core git curl wget bind-utils \
    iputils ipset iptables iproute jq cronie make gcc pkgconfig tcpdump idn2 \
    nano vim-enhanced htop

dnf config-manager --set-enabled crb

log "🌐 Настройка DNS (исправление медленного резолвинга)..."
chattr -i /etc/resolv.conf 2>/dev/null || true
cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
options timeout:1 attempts:1 rotate inet4
EOF
chattr +i /etc/resolv.conf

sed -i 's/^hosts:.*$/hosts:      files dns/' /etc/nsswitch.conf
systemctl restart systemd-resolved 2>/dev/null || true

log "📁 Создание структуры директорий..."
mkdir -p "$AMNEZIA_DIR"/{clients,server-clients,server-clients-full,lists,logs}
mkdir -p /etc/amnezia/amneziawg
chown -R "$CURRENT_USER:$CURRENT_USER" "$AMNEZIA_DIR" 2>/dev/null || true

log "⚙️  Настройка системных параметров..."
cat > /etc/sysctl.d/99-ipforward.conf << 'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=2
net.ipv4.conf.default.rp_filter=2
EOF
sysctl -p /etc/sysctl.d/99-ipforward.conf

log "⚡ Установка massdns (сверхбыстрый резолвинг)..."
cd /tmp
if [[ ! -d massdns ]]; then
    git clone https://github.com/blechschmidt/massdns.git
fi
cd massdns
make clean 2>/dev/null || true
make
cp bin/massdns /usr/local/bin/
chmod +x /usr/local/bin/massdns
restorecon -v /usr/local/bin/massdns 2>/dev/null || true

log "✅ massdns установлен: $(massdns --version 2>&1 | head -1)"