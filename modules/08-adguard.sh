#!/bin/bash
# Модуль 08: AdGuard Home

set -e

log() { echo -e "\033[0;36m[08-adguard]\033[0m $1"; }

log "🌐 Освобождение порта 53..."
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
rm -f /etc/resolv.conf
echo -e "nameserver 127.0.0.1\nnameserver 8.8.8.8" > /etc/resolv.conf
chattr +i /etc/resolv.conf 2>/dev/null || true

log "📥 Установка AdGuard Home..."
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v

log "🔥 Открытие портов..."
firewall-cmd --add-port=53/tcp --permanent
firewall-cmd --add-port=53/udp --permanent
firewall-cmd --add-port=3000/tcp --permanent
firewall-cmd --reload

log "✅ AdGuard Home установлен"
log "🌐 Веб-интерфейс: http://$PUBLIC_IP:3000"
log "⚠️  После настройки закройте порт 3000: firewall-cmd --remove-port=3000/tcp --permanent && firewall-cmd --reload"