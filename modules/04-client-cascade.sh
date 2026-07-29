#!/bin/bash
# Модуль 04: Клиент для каскада VPS-to-VPS
set -e
log() { echo -e "\033[0;36m[04-cascade]\033[0m $1"; }

log "📝 Создание Watchdog для каскада..."
cat > "$AMNEZIA_DIR/vpn-watchdog-cascade.sh" << 'SCRIPT'
#!/bin/bash
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"
LOG_FILE="$AMNEZIA_DIR/logs/vpn-watchdog-cascade.log"
ACTIVE_SERVICE="awg-quick@amnezia-client"
mkdir -p "$(dirname "$LOG_FILE")"
log_msg() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"; }

if ! ip link show amnezia-client >/dev/null 2>&1; then
    log_msg "⚠️ Интерфейс down. Поднимаем..."
    systemctl start "$ACTIVE_SERVICE"
    exit 0
fi

if ping -I amnezia-client -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
    exit 0
fi
sleep 5
if ping -I amnezia-client -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
    exit 0
fi

log_msg "❌ Связь потеряна. Перезапуск туннеля..."
systemctl restart "$ACTIVE_SERVICE"
log_msg "✅ Туннель перезапущен"
SCRIPT
chmod +x "$AMNEZIA_DIR/vpn-watchdog-cascade.sh"

log "⏰ Настройка systemd timer..."
cat > /etc/systemd/system/vpn-watchdog-cascade.service << EOF
[Unit]
Description=Cascade VPN Watchdog
After=network.target
[Service]
Type=oneshot
ExecStart=$AMNEZIA_DIR/vpn-watchdog-cascade.sh
User=root
EOF

cat > /etc/systemd/system/vpn-watchdog-cascade.timer << 'EOF'
[Unit]
Description=Run Cascade Watchdog every 60s
[Timer]
OnBootSec=1min
OnUnitActiveSec=60s
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now vpn-watchdog-cascade.timer

log "📝 Создание шаблона конфига каскада..."
cat > /etc/amnezia/amneziawg/amnezia-client.conf.template << 'EOF'
# ==============================================================================
# ШАБЛОН КОНФИГА КАСКАДА VPS-to-VPS
# Замените значения на свои и переименуйте в amnezia-client.conf
# ==============================================================================
[Interface]
PrivateKey = <ПРИВАТНЫЙ_КЛЮЧ_VPS_A>
Address = 10.8.0.2/24
Table = off
Jc = 3; Jmin = 50; Jmax = 1000; S1 = 25; S2 = 50
H1 = 12345678; H2 = 87654321; H3 = 11223344; H4 = 44332211

[Peer]
PublicKey = <ПУБЛИЧНЫЙ_КЛЮЧ_VPS_B>
Endpoint = <IP_VPS_B>:41820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
chmod 600 /etc/amnezia/amneziawg/amnezia-client.conf.template

log "✅ Каскад-клиент настроен"
log "📝 Создайте конфиг: nano /etc/amnezia/amneziawg/amnezia-client.conf"
log "📋 Шаблон: /etc/amnezia/amneziawg/amnezia-client.conf.template"