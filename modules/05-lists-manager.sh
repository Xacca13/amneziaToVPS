#!/bin/bash
# Модуль 05: Менеджер списков (update-lists.sh)
set -e
log() { echo -e "\033[0;36m[05-lists]\033[0m $1"; }

log "📝 Создание скрипта update-lists.sh..."
cat > "$AMNEZIA_DIR/update-lists.sh" << 'SCRIPT'
#!/bin/bash
# /home/user1/amnezia/update-lists.sh
# Cron: 0 */6 * * * root /home/user1/amnezia/update-lists.sh
set -o pipefail

CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

INCLUDE_URLS="$AMNEZIA_DIR/include_urls.conf"
INCLUDE_CUSTOM="$AMNEZIA_DIR/include_custom.conf"
EXCLUDE_URLS="$AMNEZIA_DIR/exclude_urls.conf"
EXCLUDE_CUSTOM="$AMNEZIA_DIR/exclude_custom.conf"

VPN_DOMAINS="$AMNEZIA_DIR/vpn-domains.conf"
VPN_BACKUP="$AMNEZIA_DIR/vpn-domains-old.conf"
DIRECT_DOMAINS="$AMNEZIA_DIR/vpn-outside.conf"
DIRECT_BACKUP="$AMNEZIA_DIR/vpn-outside-old.conf"

APPLY_SCRIPT="$AMNEZIA_DIR/apply-routes.sh"
TEMP_DIR="/tmp/amnezia-lists"
LOG_FILE="$AMNEZIA_DIR/logs/update-lists.log"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_msg() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"; }

mkdir -p "$TEMP_DIR" "$(dirname "$LOG_FILE")"
log_msg "${GREEN}🚀 Обновление списков (без резолвинга)...${NC}"

HAS_IDN2=$(command -v idn2 &>/dev/null && echo 1 || echo 0)

build_list() {
    local urls_file="$1"
    local custom_file="$2"
    local output_file="$3"
    local backup_file="$4"
    local label="$5"

    local tmp_domains="$TEMP_DIR/${label}_domains"
    local tmp_ipv4="$TEMP_DIR/${label}_ipv4"
    local tmp_ipv6="$TEMP_DIR/${label}_ipv6"
    > "$tmp_domains"; > "$tmp_ipv4"; > "$tmp_ipv6"

    # --- URL-источники ---
    if [[ -f "$urls_file" ]]; then
        while IFS= read -r url || [[ -n "$url" ]]; do
            [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue
            url=$(echo "$url" | xargs)
            local tmp="$TEMP_DIR/dl_$(date +%s%N).tmp"

            if curl -sL --fail --compressed --connect-timeout 10 --max-time 120 \
               --retry 3 -A "Mozilla/5.0" "$url" -o "$tmp" 2>/dev/null; then

                # IPv4 с валидацией
                grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' "$tmp" 2>/dev/null | \
                awk -F'[./]' '{
                    if (NF<4||NF>5) next
                    ok=1
                    for(i=1;i<=4;i++){if($i!~/^[0-9]+$/||$i+0>255)ok=0}
                    if(NF==5&&($5!~/^[0-9]+$/||$5+0>32))ok=0
                    if(ok) print
                }' >> "$tmp_ipv4"

                # IPv6
                grep -Eio '([0-9a-f]{1,4}:){2,7}[0-9a-f]{1,4}(/[0-9]{1,3})?' "$tmp" 2>/dev/null | \
                awk -F'/' '{if(NF==2&&$2+0>128)next; print}' >> "$tmp_ipv6"

                # Домены: очистка AdGuard-синтаксиса → punycode → валидация
                sed -E \
                    -e 's/#.*//' -e 's/\r//g' \
                    -e 's/^[[:space:]]+//;s/[[:space:]]+$//' \
                    -e '/^$/d' -e '/^[!;\[]/d' -e '/^\/.*\/$/d' \
                    -e 's/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+//' \
                    -e 's/^\|\|//' -e 's/\^.*$//' \
                    -e 's|^[a-zA-Z][a-zA-Z0-9+.-]*://||' \
                    -e 's/[\/?#@!$&'\''()*+,;=~].*//' \
                    -e 's/^\*\.//' -e 's/\.$//' -e '/^$/d' \
                    -e 's/.*/\L&/' \
                    "$tmp" | \
                while IFS= read -r line; do
                    if [[ "$line" =~ [^a-z0-9._-] ]]; then
                        [[ $HAS_IDN2 -eq 1 ]] && idn2 "$line" 2>/dev/null || true
                    else
                        echo "$line"
                    fi
                done | \
                grep -E '^[a-z0-9]([a-z0-9_-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9_-]{0,61}[a-z0-9])?)*\.[a-z]{2,}$' \
                >> "$tmp_domains"

                rm -f "$tmp"
                log_msg "  ✓ $url"
            else
                log_msg "  ${YELLOW}⚠ Ошибка: $url${NC}"
                rm -f "$tmp"
            fi
            sleep 1
        done < "$urls_file"
    fi

    # --- Custom-файл: БЕЗ фильтрации, только сортировка ---
    if [[ -f "$custom_file" ]]; then
        local tmp_custom="$TEMP_DIR/${label}_custom"
        sed -e 's/#.*//' -e 's/\r//g' \
            -e 's/^[[:space:]]*//;s/[[:space:]]*$//' -e '/^$/d' \
            "$custom_file" > "$tmp_custom"

        grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' "$tmp_custom" 2>/dev/null | \
        awk -F'[./]' '{
            if(NF<4||NF>5)next; ok=1
            for(i=1;i<=4;i++){if($i!~/^[0-9]+$/||$i+0>255)ok=0}
            if(NF==5&&($5!~/^[0-9]+$/||$5+0>32))ok=0
            if(ok) print
        }' >> "$tmp_ipv4"

        grep -Eio '([0-9a-f]{1,4}:){2,7}[0-9a-f]{1,4}(/[0-9]{1,3})?' "$tmp_custom" 2>/dev/null | \
        awk -F'/' '{if(NF==2&&$2+0>128)next; print}' >> "$tmp_ipv6"

        grep -vE '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$' "$tmp_custom" | \
        grep -viE '^[0-9a-f]*:[0-9a-f:]+(/[0-9]{1,3})?$' | \
        sed 's/.*/\L&/' | grep -vE '^$' >> "$tmp_domains"

        rm -f "$tmp_custom"
    fi

    # --- Дедупликация ---
    LC_ALL=C sort -u "$tmp_domains" -o "$tmp_domains"
    LC_ALL=C sort -u "$tmp_ipv4" -o "$tmp_ipv4"
    LC_ALL=C sort -u "$tmp_ipv6" -o "$tmp_ipv6"

    # --- Сравнение с текущим ---
    local new_hash=$(cat "$tmp_domains" "$tmp_ipv4" "$tmp_ipv6" | md5sum | cut -d' ' -f1)
    local old_hash=""
    [[ -f "$output_file" ]] && \
        old_hash=$(sed 's/#.*//' "$output_file" | sed '/^[[:space:]]*$/d' | md5sum | cut -d' ' -f1)

    if [[ "$new_hash" == "$old_hash" ]]; then
        log_msg "${GREEN}✅ $label: изменений нет${NC}"
        rm -f "$tmp_domains" "$tmp_ipv4" "$tmp_ipv6"
        return 1
    fi

    # --- Бэкап + запись ---
    [[ -f "$output_file" ]] && cp "$output_file" "$backup_file"
    {
        echo "# === $label === $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "# --- Домены ---"
        cat "$tmp_domains"
        echo ""
        echo "# --- IPv4 ---"
        cat "$tmp_ipv4"
        echo ""
        echo "# --- IPv6 ---"
        cat "$tmp_ipv6"
    } > "$output_file"

    local d=$(wc -l < "$tmp_domains" | tr -d ' ')
    local v4=$(wc -l < "$tmp_ipv4" | tr -d ' ')
    local v6=$(wc -l < "$tmp_ipv6" | tr -d ' ')
    log_msg "${GREEN}✅ $label: доменов=$d ipv4=$v4 ipv6=$v6${NC}"

    rm -f "$tmp_domains" "$tmp_ipv4" "$tmp_ipv6"
    return 0
}

# --- Сборка ---
changed=0
build_list "$INCLUDE_URLS" "$INCLUDE_CUSTOM" "$VPN_DOMAINS" "$VPN_BACKUP" "VPN" && changed=1
build_list "$EXCLUDE_URLS" "$EXCLUDE_CUSTOM" "$DIRECT_DOMAINS" "$DIRECT_BACKUP" "DIRECT" && changed=1
rm -rf "$TEMP_DIR"

# --- Применение ---
if [[ $changed -eq 1 ]]; then
    log_msg "🔄 Запуск apply-routes.sh..."
    if [[ -x "$APPLY_SCRIPT" ]]; then
        "$APPLY_SCRIPT" 2>&1 | tee -a "$LOG_FILE"
    else
        log_msg "${RED}❌ $APPLY_SCRIPT не найден${NC}"
    fi
else
    log_msg "🎉 Изменений нет."
fi
log_msg "🏁 Готово."
SCRIPT
chmod +x "$AMNEZIA_DIR/update-lists.sh"

log "⏰ Настройка systemd timer (автообновление каждые 6 часов)..."
cat > /etc/systemd/system/amnezia-update-lists.service << EOF
[Unit]
Description=AmneziaWG Auto Update Lists
After=network.target
[Service]
Type=oneshot
ExecStart=$AMNEZIA_DIR/update-lists.sh
User=root
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/amnezia-update-lists.timer << 'EOF'
[Unit]
Description=Run AmneziaWG Update Lists every 6 hours
Requires=amnezia-update-lists.service
[Timer]
OnCalendar=*-*-* 00/6:00:00
Persistent=true
RandomizedDelaySec=600
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now amnezia-update-lists.timer
log "✅ Менеджер списков настроен (cron каждые 6ч, без резолвинга)"