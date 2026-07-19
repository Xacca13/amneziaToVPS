#!/bin/bash
# Модуль 06: Smart Update v2.0

set -e

log() { echo -e "\033[0;36m[06-lists]\033[0m $1"; }

log "📝 Создание скрипта Smart Update v2.0..."
cat > "$AMNEZIA_DIR/update-lists.sh" << 'SCRIPT'
#!/bin/bash
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

INCLUDE_URLS="$AMNEZIA_DIR/include_urls.conf"
INCLUDE_CUSTOM="$AMNEZIA_DIR/include_custom.conf"
EXCLUDE_URLS="$AMNEZIA_DIR/exclude_urls.conf"
EXCLUDE_CUSTOM="$AMNEZIA_DIR/exclude_custom.conf"
FILTER_URLS="$AMNEZIA_DIR/filter_urls.conf"
FILTER_CUSTOM="$AMNEZIA_DIR/filter_custom.conf"
OUTPUT_DIR="$AMNEZIA_DIR/lists"
TEMP_DIR="/tmp/amnezia-lists"
LOG_FILE="$AMNEZIA_DIR/logs/update-lists.log"
VPN_DOMAINS="$AMNEZIA_DIR/vpn-domains.conf"
VPN_DOMAINS_BACKUP="$AMNEZIA_DIR/vpn-domains-old.conf"
DIRECT_DOMAINS="$AMNEZIA_DIR/vpn-outside.conf"
DIRECT_DOMAINS_BACKUP="$AMNEZIA_DIR/vpn-outside-old.conf"
UPDATE_ROUTES="$AMNEZIA_DIR/update-vpn-routes.sh"

GAMBLING_REGEX='^[0-9]+|porn|[ck]a+[szc3]+[iley1]+n+[0-9o]|[vw][uy]+[l1]+[kc]a+n|x-*bet|most-*bet|leon-*bet|rio-*bet|mel-*bet|ramen-*bet|marathon-*bet|max-*bet|bet-*win|gg-*bet|spin-*bet|banzai-*bet|1iks-*bet|x-*slot|sloto-*zal|max-*slot|bk-*leon|gold-*fishka|play-*fortuna|dragon-*money|poker-*dom|1-*win|crypto-*bos|free-*spin|fair-*spin|no-*deposit|igrovye|avtomaty|bookmaker|zerkalo|slottica|admiral-*x|x-*admiral|pinup-*bet|pari-*match|betting|partypoker|jackpot|bonus|azino[0-9-]|888-*starz|zooma[0-9-]|zenit-*bet|eldorado|slots|vodka|newretro|platinum|igrat|flagman|arkada|\.ua$|\.sex\.|^gama|^xn-+|xn-+|^wheel-.+pinco|-{2,}|(film)?.*lord.*(film)?|\.buzz$|\.pics$|\.work$|\.courses$|\.lat$|\.skin$|\.sbs$|\.kinoza\.|\.kinozi\.|\.men$|\.kz$|herrutor|prostitut'

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_msg() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"; }

mkdir -p "$OUTPUT_DIR" "$TEMP_DIR" "$(dirname "$LOG_FILE")"
log_msg "${GREEN}🚀 Запуск комплексного обновления списков...${NC}"

# ЭТАП 0: Глобальный список фильтрации
log_msg "📥 Формирование глобального списка фильтрации..."
> "$TEMP_DIR/remove-hosts-raw.txt"

if [[ -f "$FILTER_URLS" ]]; then
    while IFS= read -r url || [[ -n "$url" ]]; do
        [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue
        url=$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        temp_dl="$TEMP_DIR/filter_dl_$(date +%s%N).tmp"
        if curl -s -L --compressed -A "Mozilla/5.0" --connect-timeout 10 --max-time 60 --retry 10 --retry-delay 3 "$url" -o "$temp_dl" 2>/dev/null; then
            if [[ "$url" == *.gz ]] || file "$temp_dl" | grep -qi "gzip"; then
                gzip -dc "$temp_dl" >> "$TEMP_DIR/remove-hosts-raw.txt" 2>/dev/null
            else
                cat "$temp_dl" >> "$TEMP_DIR/remove-hosts-raw.txt"
            fi
            rm -f "$temp_dl"
            log_msg "${GREEN}✓${NC} Загружен фильтр: $url"
        else
            log_msg "${YELLOW}⚠️ Не удалось загрузить фильтр: $url${NC}"
        fi
    done < "$FILTER_URLS"
fi

[[ -f "$FILTER_CUSTOM" ]] && cat "$FILTER_CUSTOM" >> "$TEMP_DIR/remove-hosts-raw.txt"

log_msg "🧹 Очистка списка фильтрации..."
sed -E \
    -e '/^[!#\[]/d' \
    -e '/^\/.+/d' \
    -e 's/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+//' \
    -e 's/^\|\|//' \
    -e 's/\^[[:space:]]*$//' \
    -e 's/[[:space:]]+$//' \
    -e 's/.*/\L&/' \
    "$TEMP_DIR/remove-hosts-raw.txt" | \
grep -E '^[a-z0-9]' | \
sort -u > "$TEMP_DIR/remove-hosts.txt"

rm -f "$TEMP_DIR/remove-hosts-raw.txt"
REMOVE_COUNT=$(wc -l < "$TEMP_DIR/remove-hosts.txt" | tr -d ' ')
log_msg "${GREEN}✅ Глобальный список фильтрации готов (${REMOVE_COUNT} записей).${NC}"

# ЭТАП 1: Универсальная функция обработки
process_list() {
    local urls_file="$1"
    local custom_file="$2"
    local target_file="$3"
    local backup_file="$4"
    local list_name="$5"
    
    log_msg "🔄 Начало обработки списка $list_name..."
    
    local temp_domains="$TEMP_DIR/${list_name}_domains.tmp"
    local temp_ipv4="$TEMP_DIR/${list_name}_ipv4.tmp"
    local temp_ipv6="$TEMP_DIR/${list_name}_ipv6.tmp"
    
    > "$temp_domains"; > "$temp_ipv4"; > "$temp_ipv6"
    
    local CLEAN_SED='s/#.*//; s/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d; s/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+//; s/[]_~:\/?#\[@!$&'\''()*+,;=].*//; s/^\*\.//; s/\.$//; s/.*/\L&/'
    
    if [[ -f "$urls_file" ]]; then
        while IFS= read -r url || [[ -n "$url" ]]; do
            [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue
            url=$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            log_msg "📥 Скачивание ($list_name): $url"
            local temp_dl="$TEMP_DIR/dl_$(date +%s%N).tmp"
            if curl -s -L --fail --compressed -A "Mozilla/5.0" \
               --connect-timeout 10 --max-time 60 --retry 10 --retry-delay 3 \
               "$url" -o "$temp_dl" 2>/dev/null; then
                grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' "$temp_dl" >> "$temp_ipv4" 2>/dev/null
                grep -Eio '([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}(/[0-9]{1,3})?' "$temp_dl" >> "$temp_ipv6" 2>/dev/null
                sed -E "$CLEAN_SED" "$temp_dl" | \
                grep -E '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]{2,}$' | \
                grep -viE "$GAMBLING_REGEX" >> "$temp_domains"
                rm -f "$temp_dl"
                log_msg "${GREEN}✓${NC} Обработано: $url"
            else
                log_msg "${RED}✗${NC} Ошибка скачивания: $url"
            fi
            sleep 5
        done < "$urls_file"
    fi
    
    if [[ -f "$custom_file" ]]; then
        log_msg "📂 Чтение пользовательского файла ($list_name): $custom_file"
        grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' "$custom_file" >> "$temp_ipv4" 2>/dev/null
        grep -Eio '([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}(/[0-9]{1,3})?' "$custom_file" >> "$temp_ipv6" 2>/dev/null
        sed -E "$CLEAN_SED" "$custom_file" | \
        grep -E '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]{2,}$' | \
        grep -viE "$GAMBLING_REGEX" >> "$temp_domains"
    fi
    
    log_msg "🧹 Оптимизация и дедупликация..."
    sort -u "$temp_domains" -o "$temp_domains"
    
    local temp_domains_puny="$TEMP_DIR/${list_name}_domains_puny.tmp"
    if command -v idn2 &> /dev/null; then
        while IFS= read -r domain; do
            idn2 "$domain" 2>/dev/null || echo "$domain"
        done < "$temp_domains" > "$temp_domains_puny"
        mv "$temp_domains_puny" "$temp_domains"
    fi
    
    local temp_domains_filtered="$TEMP_DIR/${list_name}_domains_filtered.tmp"
    comm -13 "$TEMP_DIR/remove-hosts.txt" "$temp_domains" > "$temp_domains_filtered"
    
    sed -E '/\..*\./ s/^(www[0-9]*|m|mobile|hd|static|[0-9]+)\.//' "$temp_domains_filtered" | \
    rev | sort -u | \
    awk 'BEGIN { last = "" }
    {
        if (last != "" && index($0, last ".") == 1) { next }
        last = $0
        print $0
    }' | rev | sort -u > "${target_file}.domains.tmp"
    
    sort -u "$temp_ipv4" > "${target_file}.ipv4.tmp"
    sort -u "$temp_ipv6" > "${target_file}.ipv6.tmp"
    
    rm -f "$temp_domains" "$temp_domains_filtered"
    
    local total_combined=$(cat "${target_file}.domains.tmp" "${target_file}.ipv4.tmp" "${target_file}.ipv6.tmp" | sort -u | wc -l | tr -d ' ')
    
    local temp_current="$TEMP_DIR/${list_name}_current.tmp"
    if [[ -f "$target_file" ]]; then
        grep -vE '^#|^$' "$target_file" > "$temp_current" 2>/dev/null || true
    else
        > "$temp_current"
    fi
    
    if diff -q "$temp_current" <(cat "${target_file}.domains.tmp" "${target_file}.ipv4.tmp" "${target_file}.ipv6.tmp" | sort -u) > /dev/null 2>&1; then
        log_msg "${GREEN}✅ Списки $list_name идентичны. Обновление не требуется.${NC}"
        rm -f "${target_file}.domains.tmp" "${target_file}.ipv4.tmp" "${target_file}.ipv6.tmp" "$temp_current"
        return 0
    fi
    
    local added=$(comm -13 "$temp_current" <(cat "${target_file}.domains.tmp" "${target_file}.ipv4.tmp" "${target_file}.ipv6.tmp" | sort -u) | wc -l | tr -d ' ')
    local removed=$(comm -23 "$temp_current" <(cat "${target_file}.domains.tmp" "${target_file}.ipv4.tmp" "${target_file}.ipv6.tmp" | sort -u) | wc -l | tr -d ' ')
    
    log_msg "${YELLOW}📊 Изменения ($list_name): +$added добавлено, -$removed удалено${NC}"
    [[ -f "$target_file" ]] && cp "$target_file" "$backup_file"
    
    echo "# === Автоматически сгенерированный список для $list_name ===" > "$target_file"
    echo "# Обновлено: $(date '+%Y-%m-%d %H:%M:%S')" >> "$target_file"
    echo "" >> "$target_file"
    echo "# --- Домены ---" >> "$target_file"
    cat "${target_file}.domains.tmp" >> "$target_file"
    echo "" >> "$target_file"
    echo "# --- IPv4 ---" >> "$target_file"
    cat "${target_file}.ipv4.tmp" >> "$target_file"
    echo "" >> "$target_file"
    echo "# --- IPv6 ---" >> "$target_file"
    cat "${target_file}.ipv6.tmp" >> "$target_file"
    
    chown "$CURRENT_USER:$CURRENT_USER" "$target_file" 2>/dev/null || true
    log_msg "${GREEN}✅ ${target_file} обновлен (${total_combined} записей)${NC}"
    
    rm -f "${target_file}.domains.tmp" "${target_file}.ipv4.tmp" "${target_file}.ipv6.tmp" "$temp_current"
    return 1
}

# ЭТАП 2: Запуск обработки
vpn_changed=0
direct_changed=0

process_list "$INCLUDE_URLS" "$INCLUDE_CUSTOM" "$VPN_DOMAINS" "$VPN_DOMAINS_BACKUP" "VPN"
vpn_changed=$?

process_list "$EXCLUDE_URLS" "$EXCLUDE_CUSTOM" "$DIRECT_DOMAINS" "$DIRECT_DOMAINS_BACKUP" "DIRECT"
direct_changed=$?

# ЭТАП 3: Применение изменений
if [[ $vpn_changed -eq 1 || $direct_changed -eq 1 ]]; then
    log_msg ""
    log_msg "${CYAN}🛣 Обнаружены изменения. Запуск резолвинга...${NC}"
    if [[ -x "$UPDATE_ROUTES" ]]; then
        if "$UPDATE_ROUTES" 2>&1 | tee -a "$LOG_FILE"; then
            log_msg "${GREEN}✅ Правила маршрутизации обновлены!${NC}"
        else
            log_msg "${RED}❌ Ошибка при обновлении правил!${NC}"
        fi
    fi
else
    log_msg "${GREEN}🎉 Изменений не обнаружено.${NC}"
fi

rm -rf "$TEMP_DIR"
log_msg "${GREEN}🏁 Полный цикл обновления завершен!${NC}"
SCRIPT

chmod +x "$AMNEZIA_DIR/update-lists.sh"

log "⏰ Настройка systemd timer (автообновление раз в неделю)..."
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
Description=Run AmneziaWG Update Lists weekly
Requires=amnezia-update-lists.service

[Timer]
OnCalendar=Sun 03:00:00
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now amnezia-update-lists.timer

log "✅ Smart Update v2.0 настроен"