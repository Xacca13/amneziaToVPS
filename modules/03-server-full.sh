#!/bin/bash
# Модуль 03: Сервер Full Tunnel (порт 41821)

set -e

log() { echo -e "\033[0;36m[03-full]\033[0m $1"; }

SERVER_PORT=41821
SERVER_INTERFACE="awg-server2"
CLIENT_DIR="$AMNEZIA_DIR/server-clients-full"

log "🔑 Генерация ключей сервера..."
SERVER_PRIV=$(awg genkey)
SERVER_PUB=$(echo "$SERVER_PRIV" | awg pubkey)

log "📝 Создание конфигурации сервера..."
cat > /etc/amnezia/amneziawg/${SERVER_INTERFACE}.conf << EOF
[Interface]
PrivateKey = $SERVER_PRIV
Address = 10.9.0.1/24
ListenPort = $SERVER_PORT
Jc = 3
Jmin = 50
Jmax = 1000
S1 = 25
S2 = 50
H1 = 12345678
H2 = 87654321
H3 = 11223344
H4 = 44332211
PostUp = iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.9.0.0/24 -j MASQUERADE
EOF

log "👥 Генерация $CLIENT_COUNT клиентских конфигов..."
for i in $(seq 1 "$CLIENT_COUNT"); do
    CLIENT_NUM=$(printf "%02d" $i)
    CLIENT_IP="10.9.0.$((i + 1))"
    CLIENT_PRIV=$(awg genkey)
    CLIENT_PUB=$(echo "$CLIENT_PRIV" | awg pubkey)

    cat >> /etc/amnezia/amneziawg/${SERVER_INTERFACE}.conf << EOF

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = $CLIENT_IP/32
EOF

    cat > "$CLIENT_DIR/client_${CLIENT_NUM}.conf" << EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP/24
DNS = 10.9.0.1
Jc = 3
Jmin = 50
Jmax = 1000
S1 = 25
S2 = 50
H1 = 12345678
H2 = 87654321
H3 = 11223344
H4 = 44332211

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBLIC_IP:$SERVER_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
done

chmod 600 /etc/amnezia/amneziawg/${SERVER_INTERFACE}.conf
chown -R "$CURRENT_USER:$CURRENT_USER" "$CLIENT_DIR"

log "🚀 Запуск сервиса..."
systemctl enable --now awg-quick@${SERVER_INTERFACE}

log "🔥 Открытие порта в firewall..."
firewall-cmd --add-port=${SERVER_PORT}/udp --permanent
firewall-cmd --reload

log "✅ Full Tunnel сервер готов (порт $SERVER_PORT)"
log "📁 Клиентские конфиги: $CLIENT_DIR/"