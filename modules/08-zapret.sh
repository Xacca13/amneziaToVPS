#!/bin/bash
# Модуль 09: Zapret 2

set -e

log() { echo -e "\033[0;36m[09-zapret]\033[0m $1"; }

log "📦 Установка зависимостей..."
dnf install -y luajit-devel lua-devel libcap-devel \
    libnetfilter_queue-devel libmnl-devel zlib-devel systemd-devel

log "📥 Клонирование Zapret..."
cd /opt
if [[ ! -d zapret ]]; then
    git clone https://github.com/bol-van/zapret.git
fi
cd zapret

log "⚙️  Запуск установщика..."
log "⚠️  ВАЖНО: В интерактивном меню выберите:"
log "   - Фаервол: nftables"
log "   - Стратегия: desync или fake"
log ""

./install_easy.sh

log "✅ Zapret установлен"