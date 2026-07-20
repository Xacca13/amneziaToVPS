#!/bin/bash
# Модуль 11: Синхронизация vpn-domains.conf → Zapret2

set -e

log() { echo -e "\033[0;36m[11-zapret-sync]\033[0m $1"; }

# Проверка наличия Zapret
if [[ ! -d "/opt/zapret2" ]]; then
    log "⚠️ Zapret2 не установлен. Пропускаем синхронизацию."
    exit 0
fi

ZAPRET_LISTS_DIR="/opt/zapret2/lists"
TARGET_DOMAINS="$ZAPRET_LISTS_DIR/vpn-domains.txt"
TARGET_IPV4="$ZAPRET_LISTS_DIR/vpn-ipv4.txt"
TARGET_IPV6="$ZAPRET_LISTS_DIR/vpn-ipv6.txt"

log "🔄 Начало синхронизации списков с Zapret2..."

mkdir -p "$ZAPRET_LISTS_DIR"

if [[ ! -f "$AMNEZIA_DIR/vpn-domains.conf" ]]; then
    log "⚠️ Файл vpn-domains.conf не найден. Пропускаем."
    exit 0
fi

TEMP_CLEAN=$(mktemp)
TEMP_DOMAINS=$(mktemp)
TEMP_IPV4=$(mktemp)
TEMP_IPV6=$(mktemp)

# Очистка и разделение
sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' "$AMNEZIA_DIR/vpn-domains.conf" | \
grep -v '^$' | tr '[:upper:]' '[:lower:]' | sort -u > "$TEMP_CLEAN"

awk '
{
    line = $1
    if (line ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$/) { print line > "'"$TEMP_IPV4"'" }
    else if (line ~ /^[0-9a-f:]+(\/[0-9]+)?$/ && line ~ /:/) { print line > "'"$TEMP_IPV6"'" }
    else if (line ~ /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]{2,}$/) { print line > "'"$TEMP_DOMAINS"'" }
}
' "$TEMP_CLEAN"

DOMAINS_COUNT=$(wc -l < "$TEMP_DOMAINS" 2>/dev/null | tr -d ' ' || echo 0)
IPV4_COUNT=$(wc -l < "$TEMP_IPV4" 2>/dev/null | tr -d ' ' || echo 0)

[[ -z "$DOMAINS_COUNT" ]] && DOMAINS_COUNT=0
[[ -z "$IPV4_COUNT" ]] && IPV4_COUNT=0

log "📊 Распределение: 🌐 Доменов: $DOMAINS_COUNT | 📡 IPv4: $IPV4_COUNT"

if [[ "$DOMAINS_COUNT" -gt 0 ]]; then
    mv "$TEMP_DOMAINS" "$TARGET_DOMAINS"
    chmod 644 "$TARGET_DOMAINS"
else
    > "$TARGET_DOMAINS"; chmod 644 "$TARGET_DOMAINS"
    rm -f "$TEMP_DOMAINS"
fi

if [[ "$IPV4_COUNT" -gt 0 ]]; then
    mv "$TEMP_IPV4" "$TARGET_IPV4"
    chmod 644 "$TARGET_IPV4"
else
    > "$TARGET_IPV4"; chmod 644 "$TARGET_IPV4"
    rm -f "$TEMP_IPV4"
fi

rm -f "$TEMP_CLEAN" "$TEMP_IPV6"

# Перезапуск Zapret2
log "🔄 Перезапуск сервиса Zapret2..."
if systemctl list-unit-files zapret2.service &>/dev/null && (systemctl is-active --quiet zapret2.service 2>/dev/null || systemctl list-unit-files zapret2.service 2>/dev/null | grep -q "zapret2.service"); then
    if systemctl restart zapret2.service 2>/dev/null; then
        log "✅ Сервис zapret2.service перезапущен через systemd"
    else
        log "⚠️ Не удалось перезапустить через systemd"
    fi
elif [[ -x "/opt/zapret2/init.d/sysv/zapret2" ]]; then
    "/opt/zapret2/init.d/sysv/zapret" restart &>/dev/null && log "✅ Перезапущен через init.d" || log "⚠️ Ошибка перезапуска init.d"
else
    log "⚠️ Сервис не найден. Перезапустите Zapret вручную, если необходимо."
fi

log "✅ Синхронизация с Zapret завершена!"