#!/bin/bash
# Модуль 04: Клиент с автопереключением (режим Мульти-конфиги)

set -e

log() { echo -e "\033[0;36m[04-multi]\033[0m $1"; }

CLIENT_DIR="$AMNEZIA_DIR/clients"

log "📝 Создание скрипта автопереключения (switch-vpn.sh)..."
cat > "$AMNEZIA_DIR/switch-vpn.sh" << 'SCRIPT'
#!/bin/bash
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"
CLIENT_DIR="$AMNEZIA_DIR/clients"
ACTIVE_CONF="/etc/amnezia/amneziawg/amnezia-client.conf"
ACTIVE_SERVICE="awg-quick@amnezia-client"
UPDATE_ROUTES="$AMNEZIA_DIR/update-vpn-routes.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

EXCLUDE_CONF=""
if [[ "$1" == "--exclude" ]]; then EXCLUDE_CONF="$2"; fi

BEST_CONF=""; BEST_PING=9999; BEST_SPEED=0; TOTAL=0; VALID=0

echo -e "${CYAN}🔍 Проверка VPN-серверов...${NC}"
[[ -n "$EXCLUDE_CONF" ]] && echo -e "${YELLOW}⚠️ Исключен: $EXCLUDE_CONF${NC}"

for conf in "$CLIENT_DIR"/*.conf; do
    [[ ! -f "$conf" ]] && continue
    ((TOTAL++))
    conf_name=$(basename "$conf")
    
    [[ "$conf_name" == "$EXCLUDE_CONF" ]] && { 
        echo -e "${YELLOW}⏭️ [$TOTAL] Пропускаем: $conf_name${NC}"; 
        continue; 
    }
    
    echo -n "🔄 [$TOTAL] Тестируем $conf_name ... "
    
    cp "$conf" "$ACTIVE_CONF"; chmod 600 "$ACTIVE_CONF"
    systemctl start "$ACTIVE_SERVICE" 2>/dev/null; sleep 5
    
    handshake=$(awg show amnezia-client 2>/dev/null | grep "latest handshake" | awk '{print $3, $4, $5}')
    if [[ "$handshake" == "(none)" || -z "$handshake" ]]; then
        echo -e "${RED}✗ Нет handshake${NC}"
        systemctl stop "$ACTIVE_SERVICE" 2>/dev/null; sleep 3; continue
    fi
    
    ping_time=$(ping -I amnezia-client -c 3 -W 2 1.1.1.1 2>/dev/null | awk -F'/' '/rtt/ {print $5}')
    if [[ -z "$ping_time" ]]; then
        echo -e "${RED}✗ Трафик не проходит${NC}"
        systemctl stop "$ACTIVE_SERVICE" 2>/dev/null; sleep 3; continue
    fi
    
    speed_time=$(curl -s -o /dev/null -w "%{time_total}" --interface amnezia-client \
        --connect-timeout 4 --max-time 6 "https://speed.cloudflare.com/__down?bytes=100000" 2>/dev/null)
    [[ -z "$speed_time" || "$speed_time" == "0.000" ]] && speed_time="5.0"
    
    speed_mbps=$(awk -v t="$speed_time" 'BEGIN { if(t>0) printf "%.2f", 0.8/t; else print "0.00" }')
    
    echo -e "${GREEN}✓${NC} Пинг: ${YELLOW}${ping_time} мс${NC}, Скорость: ${CYAN}${speed_mbps} Мбит/с${NC}"
    ((VALID++))
    
    is_better=$(awk -v p="$ping_time" -v bp="$BEST_PING" -v s="$speed_mbps" -v bs="$BEST_SPEED" 'BEGIN {
        if (s < 1.0) { print 0; exit }
        if (bp == 9999) { print 1; exit }
        if (p + 0 < bp + 0) { print 1; exit }
        if (p + 0 == bp + 0 && s + 0 > bs + 0) { print 1; exit }
        print 0;
    }')
    
    [[ "$is_better" == "1" ]] && { BEST_PING="$ping_time"; BEST_SPEED="$speed_mbps"; BEST_CONF="$conf"; }
    
    systemctl stop "$ACTIVE_SERVICE" 2>/dev/null; sleep 3
done

[[ -z "$BEST_CONF" ]] && { echo -e "${RED}❌ Нет рабочих серверов!${NC}"; exit 1; }

best_name=$(basename "$BEST_CONF")
echo -e "\n${GREEN}🏆 Лучший: $best_name${NC} (Пинг: $BEST_PING мс | Скорость: $BEST_SPEED Мбит/с)"

cp "$BEST_CONF" "$ACTIVE_CONF"; chmod 600 "$ACTIVE_CONF"
systemctl start "$ACTIVE_SERVICE" 2>/dev/null
sleep 2

"$UPDATE_ROUTES" --fast > /dev/null 2>&1
echo -e "${GREEN}✅ Переключено на $best_name${NC}"
SCRIPT
chmod +x "$AMNEZIA_DIR/switch-vpn.sh"

log "📝 Создание Watchdog..."
cat > "$AMNEZIA_DIR/vpn-watchdog.sh" << 'SCRIPT'
#!/bin/bash
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"
CLIENT_DIR="$AMNEZIA_DIR/clients"
ACTIVE_CONF="/etc/amnezia/amneziawg/amnezia-client.conf"
SWITCH_SCRIPT="$AMNEZIA_DIR/switch-vpn.sh"
LOG_FILE="$AMNEZIA_DIR/logs/vpn-watchdog.log"

mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"; }

if ! ip link show amnezia-client >/dev/null 2>&1; then
    log "⚠️ Интерфейс не активен. Аварийное переключение..."
    "$SWITCH_SCRIPT"; exit 0
fi

if ping -I amnezia-client -c 3 -W 2 1.1.1.1 >/dev/null 2>&1; then exit 0; fi
sleep 5
if ping -I amnezia-client -c 3 -W 2 1.1.1.1 >/dev/null 2>&1; then exit 0; fi

log "❌ Нестабильность соединения. Инициируем переключение..."

CURRENT_HOST=$(grep -i '^Endpoint' "$ACTIVE_CONF" 2>/dev/null | cut -d'=' -f2 | xargs | cut -d':' -f1)
CURRENT_CONF_NAME=""
for conf in "$CLIENT_DIR"/*.conf; do
    [[ ! -f "$conf" ]] && continue
    ep=$(grep -i '^Endpoint' "$conf" 2>/dev/null | cut -d'=' -f2 | xargs)
    h=$(echo "$ep" | cut -d':' -f1)
    if [[ "$h" == "$CURRENT_HOST" ]]; then CURRENT_CONF_NAME=$(basename "$conf"); break; fi
done

if [[ -n "$CURRENT_CONF_NAME" ]]; then
    log "🚫 Исключаем сбойный конфиг: $CURRENT_CONF_NAME"
    "$SWITCH_SCRIPT" --exclude "$CURRENT_CONF_NAME"
else
    "$SWITCH_SCRIPT"
fi

log "✅ Переключение завершено."
SCRIPT
chmod +x "$AMNEZIA_DIR/vpn-watchdog.sh"

log "⏰ Настройка systemd timers..."
cat > /etc/systemd/system/amnezia-switcher.service << EOF
[Unit]
Description=AmneziaWG Client Auto-Switcher
After=network.target

[Service]
Type=oneshot
ExecStart=$AMNEZIA_DIR/switch-vpn.sh
User=root
EOF

cat > /etc/systemd/system/amnezia-switcher.timer << 'EOF'
[Unit]
Description=Run AmneziaWG Auto-Switcher every 12 hours

[Timer]
OnCalendar=*-*-* 00/12:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/vpn-watchdog.service << EOF
[Unit]
Description=AmneziaWG Connection Watchdog
After=network.target awg-quick@amnezia-client.service

[Service]
Type=oneshot
ExecStart=$AMNEZIA_DIR/vpn-watchdog.sh
User=root
EOF

cat > /etc/systemd/system/vpn-watchdog.timer << 'EOF'
[Unit]
Description=Run VPN Watchdog every 60 seconds

[Timer]
OnBootSec=1min
OnUnitActiveSec=60s
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now amnezia-switcher.timer
systemctl enable --now vpn-watchdog.timer

log "✅ Мульти-клиент настроен"
log "📁 Загрузите конфиги провайдеров в: $CLIENT_DIR/"
log "⚠️  В каждом .conf удалите DNS= и добавьте Table=off в [Interface]"