#!/bin/bash
# Модуль 10: Синхронизация vpn-domains.conf → Zapret2
set -e
log() { echo -e "\033[0;36m[10-zapret-sync]\033[0m $1"; }

if [[ ! -d "/opt/zapret2" ]]; then
    log "⚠️ Zapret2 не установлен. Пропускаем."
    exit 0
fi

ZAPRET_LISTS_DIR="/opt/zapret2/lists"
TARGET_DOMAINS="$ZAPRET_LISTS_DIR/vpn-domains.txt"
TARGET_IPV4="$ZAPRET_LISTS_DIR/vpn-ipv4.txt"
TARGET_IPV6="$ZAPRET_LISTS_DIR/vpn-ipv6.txt"

log "🔄 Синхронизация списков с Zapret2..."
mkdir -p "$ZAPRET_LISTS_DIR"

if [[ ! -f "$AMNEZIA_DIR/vpn-domains.conf" ]]; then
    log "⚠️ vpn-domains.conf не найден."
    exit 0
fi

TEMP_CLEAN=$(mktemp)
TEMP_DOMAINS=$(mktemp)
TEMP_IPV4=$(mktemp)
TEMP_IPV6=$(mktemp)

sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' "$AMNEZIA_DIR/vpn-domains.conf" | \
    grep -v '^$' | tr '[:upper:]' '[:lower:]' | LC_ALL=C sort -u > "$TEMP_CLEAN"

awk '
{
    line = $1
    if (line ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$/) { print line > "'"$TEMP_IPV4"'" }
    else if (line ~ /^[0-9a-f:]+(\/[0-9]+)?$/ && line ~ /:/) { print line > "'"$TEMP_IPV6"'" }
    else if (line ~ /^[a-z0-9]/) { print line > "'"$TEMP_DOMAINS"'" }
}
' "$TEMP_CLEAN"

DOMAINS_COUNT=$(wc -l < "$TEMP_DOMAINS" 2>/dev/null | tr -d ' ' || echo 0)
IPV4_COUNT=$(wc -l < "$TEMP_IPV4" 2>/dev/null | tr -d ' ' || echo 0)
[[ -z "$DOMAINS_COUNT" ]] && DOMAINS_COUNT=0
[[ -z "$IPV4_COUNT" ]] && IPV4_COUNT=0

log "📊 Доменов: $DOMAINS_COUNT | IPv4: $IPV4_COUNT"

[[ "$DOMAINS_COUNT" -gt 0 ]] && mv "$TEMP_DOMAINS" "$TARGET_DOMAINS" || { > "$TARGET_DOMAINS"; rm -f "$TEMP_DOMAINS"; }
[[ "$IPV4_COUNT" -gt 0 ]] && mv "$TEMP_IPV4" "$TARGET_IPV4" || { > "$TARGET_IPV4"; rm -f "$TEMP_IPV4"; }
chmod 644 "$TARGET_DOMAINS" "$TARGET_IPV4" 2>/dev/null
rm -f "$TEMP_CLEAN" "$TEMP_IPV6"

log "🔄 Перезапуск Zapret2..."
if systemctl list-unit-files zapret2.service &>/dev/null; then
    systemctl restart zapret2.service 2>/dev/null && log "✅ Перезапущен" || log "⚠️ Ошибка перезапуска"
elif [[ -x "/opt/zapret2/init.d/sysv/zapret" ]]; then
    /opt/zapret2/init.d/sysv/zapret restart &>/dev/null && log "✅ Перезапущен" || log "⚠️ Ошибка"
fi

log "✅ Синхронизация завершена"