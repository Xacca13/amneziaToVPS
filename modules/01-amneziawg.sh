#!/bin/bash
# Модуль 01: Установка AmneziaWG

set -e

log() { echo -e "\033[0;36m[01-amnezia]\033[0m $1"; }

log "📦 Подключение репозитория AmneziaWG..."
dnf copr enable -y amneziavpn/amneziawg

log "📦 Установка AmneziaWG..."
dnf install -y amneziawg-tools amneziawg-dkms dkms kernel-devel kernel-headers

log "🔧 Сборка модуля ядра..."
dkms autoinstall

log "🚀 Загрузка модуля..."
modprobe amneziawg

if lsmod | grep -q amnezia; then
    log "✅ AmneziaWG успешно установлен и загружен"
else
    echo -e "\033[0;31m❌ Модуль amneziawg не загружен!\033[0m"
    exit 1
fi