#!/bin/bash
# Модуль 08: AdGuard Home

set -e

log() { echo -e "\033[0;36m[08-adguard]\033[0m $1"; }

log "🌐 Освобождение порта 53..."
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
rm -f /etc/resolv.conf
echo -e "nameserver 127.0.0.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf 2>/dev/null || true

log "📥 Установка AdGuard Home..."
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v

# ==============================================================================
# Проверка и настройка брандмауэра
# ==============================================================================
log "🔥 Проверка брандмауэра..."

HAS_FIREWALLD=0
HAS_UFW=0

if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
    HAS_FIREWALLD=1
fi

if command -v ufw &> /dev/null && ufw status 2>/dev/null | grep -q "active"; then
    HAS_UFW=1
fi

if [[ $HAS_FIREWALLD -eq 1 ]]; then
    log "   ✅ Обнаружен firewalld. Открываем порты 53/tcp, 53/udp, 3000/tcp..."
    firewall-cmd --add-port=53/tcp --permanent
    firewall-cmd --add-port=53/udp --permanent
    firewall-cmd --add-port=3000/tcp --permanent
    firewall-cmd --reload
elif [[ $HAS_UFW -eq 1 ]]; then
    log "   ✅ Обнаружен ufw. Открываем порты 53/tcp, 53/udp, 3000/tcp..."
    ufw allow 53/tcp
    ufw allow 53/udp
    ufw allow 3000/tcp
else
    log "   ⚠️ Активный локальный брандмауэр (firewalld/ufw) не обнаружен. Пропускаем."
fi

# ==============================================================================
# Финальные сообщения и напоминания
# ==============================================================================
log "✅ AdGuard Home успешно установлен"
log "🌐 Веб-интерфейс: http://$PUBLIC_IP:3000"

echo ""
echo -e "\033[1;33m⚠️  ВАЖНОЕ НАПОМИНАНИЕ О ПОРТАХ:\033[0m"
echo -e "Если вы используете облачный VPS (Yandex Cloud, Selectel, Timeweb, AWS, DigitalOcean и т.д.),"
echo -e "убедитесь, что порты \033[1;36m53 (TCP и UDP)\033[0m и \033[1;36m3000 (TCP)\033[0m открыты"
echo -e "в панели управления вашего хостинг-провайдера (раздел Security Groups / Сетевой экран)."
echo -e "Без этого AdGuard Home не будет отвечать на запросы извне, даже если локальный фаервол настроен."
echo ""

echo -e "\033[1;31m🔒 ПОСЛЕ ПЕРВОНАЧАЛЬНОЙ НАСТРОЙКИ настоятельно рекомендуется закрыть порт 3000:\033[0m"
if [[ $HAS_FIREWALLD -eq 1 ]]; then
    echo -e "   \033[0;36mfirewall-cmd --remove-port=3000/tcp --permanent && firewall-cmd --reload\033[0m"
elif [[ $HAS_UFW -eq 1 ]]; then
    echo -e "   \033[0;36mufw delete allow 3000/tcp\033[0m"
else
    echo -e "   \033[0;36m(Закройте порт 3000 в панели управления вашего хостинг-провайдера)\033[0m"
fi
echo ""