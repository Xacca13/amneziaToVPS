#!/bin/bash
# Модуль 07: Главный скрипт обновления маршрутов

set -e

log() { echo -e "\033[0;36m[07-routes]\033[0m $1"; }

log "📝 Создание скрипта update-vpn-routes.sh..."
cat > "$AMNEZIA_DIR/update-vpn-routes.sh" << 'SCRIPT'
#!/bin/bash
# === Основные настройки ===
IPSET_VPN="vpn_routes"
IPSET_DIRECT="vpn_direct"
IPSET_VPN6="vpn_routes6"
IPSET_DIRECT6="vpn_direct6"
MARK_VPN="0x1000"
MARK_DIRECT="0x3000"
TABLE_VPN="100"
TABLE_FULL="200"
VPN_INTERFACE="amnezia-client"
CLIENT_INTERFACE="awg-server"

CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"
CONF_VPN="$AMNEZIA_DIR/vpn-domains.conf"
CONF_DIRECT="$AMNEZIA_DIR/vpn-outside.conf"
TMP_VPN="${IPSET_VPN}_tmp"
TMP_DIRECT="${IPSET_DIRECT}_tmp"
TMP_VPN6="${IPSET_VPN6}_tmp"
TMP_DIRECT6="${IPSET_DIRECT6}_tmp"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAST_MODE=0
if [[ "$1" == "--fast" ]]; then
    FAST_MODE=1
    echo -e "${YELLOW}⚡ Быстрый режим: пропускаем резолвинг${NC}"
fi

echo "🔄 Начало обновления маршрутов..."

# === 0. Регистрация таблиц ===
grep -q "^100 " /etc/iproute2/rt_tables 2>/dev/null || echo "100 vpn_split" >> /etc/iproute2/rt_tables
grep -q "^200 " /etc/iproute2/rt_tables 2>/dev/null || echo "200 vpn_full" >> /etc/iproute2/rt_tables

sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv4.conf.all.rp_filter=2 >/dev/null
sysctl -w net.ipv4.conf.default.rp_filter=2 >/dev/null
for iface in $(ls /proc/sys/net/ipv4/conf/); do
    sysctl -w "net.ipv4.conf.$iface.rp_filter=2" >/dev/null 2>&1
done

# === 0.5. Защита SSH ===
SSH_IP=$(who am i 2>/dev/null | awk '{print $5}' | sed 's/(//;s/)//' | cut -d':' -f1)
if [[ -n "$SSH_IP" && "$SSH_IP" != "tty" && "$SSH_IP" != ":0" ]]; then
    ip rule del from all to $SSH_IP/32 table main priority 1 2>/dev/null || true
    ip rule add from all to $SSH_IP/32 table main priority 1
    echo -e "🛡️ Ваш SSH IP (${GREEN}$SSH_IP${NC}) защищен (priority 1)"
fi

# === 1. Резолвинг доменов ===
if [[ $FAST_MODE -eq 0 ]]; then
    for set in $TMP_VPN $TMP_DIRECT; do
        ipset destroy $set 2>/dev/null
        ipset create $set hash:net family inet hashsize 65536 maxelem 262144
    done
    for set in $TMP_VPN6 $TMP_DIRECT6; do
        ipset destroy $set 2>/dev/null
        ipset create $set hash:net family inet6 hashsize 65536 maxelem 262144
    done
    
    TMP_IPSET_CMD=$(mktemp)
    
    process_config() {
        local conf_file="$1"
        local set_v4="$2"
        local set_v6="$3"
        local label="$4"
        
        if [[ ! -f "$conf_file" ]]; then
            echo -e "${RED}❌ Файл $conf_file не найден!${NC}"
            return 1
        fi
        
        echo "🌐 $label: Обработка конфигурации..."
        
        local tmp_clean=$(mktemp)
        local tmp_static_v4=$(mktemp)
        local tmp_static_v6=$(mktemp)
        local tmp_domains_raw=$(mktemp)
        local tmp_domains_unique=$(mktemp)
        local tmp_resolved=$(mktemp)
        
        sed 's/#.*//' "$conf_file" | tr -d '\r' > "$tmp_clean"
        
        awk -v v4="add $set_v4" -v v6="add $set_v6" '
        NF {
            item = $1
            if (item ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$/) {
                print v4, item > "/dev/stderr"
            }
            else if (item ~ /^[0-9a-fA-F:]+(\/[0-9]+)?$/) {
                print v6, item > "/dev/stderr"
            }
            else if (item ~ /^[a-zA-Z0-9]/) {
                print item
            }
        }
        ' "$tmp_clean" > "$tmp_domains_raw" 2> >(cat > "$tmp_static_combined.tmp")
        
        grep "^add $set_v4 " "$tmp_static_combined.tmp" > "$tmp_static_v4" 2>/dev/null || true
        grep "^add $set_v6 " "$tmp_static_combined.tmp" > "$tmp_static_v6" 2>/dev/null || true
        rm -f "$tmp_static_combined.tmp"
        
        local static_count=$(($(wc -l < "$tmp_static_v4") + $(wc -l < "$tmp_static_v6")))
        echo "  📌 Статических IP в очереди: $static_count"
        
        sort -u "$tmp_domains_raw" > "$tmp_domains_unique"
        local total_unique_domains=$(wc -l < "$tmp_domains_unique" | tr -d ' ')
        echo "  🔄 Уникальных доменов для резолвинга: $total_unique_domains"
        
        if [[ $total_unique_domains -gt 0 ]]; then
            echo "  ⚡ Запуск massdns..."
            local tmp_resolvers=$(mktemp)
            echo "127.0.0.1" > "$tmp_resolvers"
            echo "9.9.9.9" >> "$tmp_resolvers"
            echo "1.1.1.1" >> "$tmp_resolvers"
            
            local tmp_resolved_raw=$(mktemp)
            massdns -r "$tmp_resolvers" -t A -t AAAA -o S -w "$tmp_resolved_raw" "$tmp_domains_unique" 2>/dev/null
            
            awk -v v4="add $set_v4" -v v6="add $set_v6" '
            / IN A / { print v4, $NF }
            / IN AAAA / { print v6, $NF }
            ' "$tmp_resolved_raw" >> "$tmp_resolved"
            
            rm -f "$tmp_resolvers" "$tmp_resolved_raw"
            echo -e "  ${GREEN}✅ $label: Резолвинг завершен.${NC}"
        else
            echo "  ⏭️ Доменов для резолвинга нет."
        fi
        
        cat "$tmp_static_v4" "$tmp_static_v6" "$tmp_resolved" | sort -u >> "$TMP_IPSET_CMD"
        rm -f "$tmp_clean" "$tmp_static_v4" "$tmp_static_v6" "$tmp_domains_raw" "$tmp_domains_unique" "$tmp_resolved"
    }
    
    process_config "$CONF_VPN" "$TMP_VPN" "$TMP_VPN6" "VPN"
    process_config "$CONF_DIRECT" "$TMP_DIRECT" "$TMP_DIRECT6" "Direct"
    
    if [[ -s "$TMP_IPSET_CMD" ]]; then
        echo "💾 Применяем изменения в ipset..."
        ipset restore -exist < "$TMP_IPSET_CMD" 2>/dev/null
    fi
    
    rm -f "$TMP_IPSET_CMD"
    
    for name in $IPSET_VPN $IPSET_DIRECT; do
        tmp="${name}_tmp"
        if ipset list "$name" >/dev/null 2>&1; then ipset swap "$tmp" "$name"; else ipset rename "$tmp" "$name"; fi
    done
    for name in $IPSET_VPN6 $IPSET_DIRECT6; do
        tmp="${name}_tmp"
        if ipset list "$name" >/dev/null 2>&1; then ipset swap "$tmp" "$name"; else ipset rename "$tmp" "$name"; fi
    done
    
    ipset destroy $TMP_VPN 2>/dev/null
    ipset destroy $TMP_DIRECT 2>/dev/null
    ipset destroy $TMP_VPN6 2>/dev/null
    ipset destroy $TMP_DIRECT6 2>/dev/null
else
    echo -e "${YELLOW}⏭️ Пропускаем резолвинг${NC}"
fi

# === 2. Таблицы маршрутизации ===
ip route flush table $TABLE_VPN 2>/dev/null || true
ip route flush table $TABLE_FULL 2>/dev/null || true
ip route add default dev $VPN_INTERFACE table $TABLE_VPN
ip route add default dev $VPN_INTERFACE table $TABLE_FULL

# === 3. ip rule ===
ip rule del from all to $SSH_IP/32 table main priority 1 2>/dev/null || true
[[ -n "$SSH_IP" ]] && ip rule add from all to $SSH_IP/32 table main priority 1

ip rule del fwmark 0x2000 table 200 2>/dev/null || true
ip rule add fwmark 0x2000 table 200 priority 2

ip rule del fwmark $MARK_VPN table $TABLE_VPN 2>/dev/null || true
ip rule add fwmark $MARK_VPN table $TABLE_VPN priority 3

ip rule del fwmark $MARK_DIRECT table main 2>/dev/null || true
ip rule add fwmark $MARK_DIRECT table main priority 4

# === 4-5. iptables mangle ===
iptables -t mangle -D PREROUTING -m set --match-set $IPSET_VPN dst -j MARK --set-mark $MARK_VPN 2>/dev/null
iptables -t mangle -D OUTPUT -m set --match-set $IPSET_VPN dst -j MARK --set-mark $MARK_VPN 2>/dev/null
iptables -t mangle -A PREROUTING -m set --match-set $IPSET_VPN dst -j MARK --set-mark $MARK_VPN
iptables -t mangle -A OUTPUT -m set --match-set $IPSET_VPN dst -j MARK --set-mark $MARK_VPN

iptables -t mangle -D PREROUTING -m set --match-set $IPSET_DIRECT dst ! -s 10.9.0.0/24 -j MARK --set-mark $MARK_DIRECT 2>/dev/null
iptables -t mangle -D OUTPUT -m set --match-set $IPSET_DIRECT dst ! -s 10.9.0.0/24 -j MARK --set-mark $MARK_DIRECT 2>/dev/null
iptables -t mangle -A PREROUTING -m set --match-set $IPSET_DIRECT dst ! -s 10.9.0.0/24 -j MARK --set-mark $MARK_DIRECT
iptables -t mangle -A OUTPUT -m set --match-set $IPSET_DIRECT dst ! -s 10.9.0.0/24 -j MARK --set-mark $MARK_DIRECT

# === 6. IPv6 ===
ip6tables -t mangle -D PREROUTING -m set --match-set $IPSET_VPN6 dst -j MARK --set-mark $MARK_VPN 2>/dev/null
ip6tables -t mangle -A PREROUTING -m set --match-set $IPSET_VPN6 dst -j MARK --set-mark $MARK_VPN
ip6tables -t mangle -D PREROUTING -m set --match-set $IPSET_DIRECT6 dst -j MARK --set-mark $MARK_DIRECT 2>/dev/null
ip6tables -t mangle -A PREROUTING -m set --match-set $IPSET_DIRECT6 dst -j MARK --set-mark $MARK_DIRECT

# === 7. NAT и FORWARD ===
iptables -t nat -D POSTROUTING -o $VPN_INTERFACE -j MASQUERADE 2>/dev/null
iptables -t nat -A POSTROUTING -o $VPN_INTERFACE -j MASQUERADE

iptables -D FORWARD -i $CLIENT_INTERFACE -o $VPN_INTERFACE -j ACCEPT 2>/dev/null
iptables -I FORWARD 1 -i $CLIENT_INTERFACE -o $VPN_INTERFACE -j ACCEPT
iptables -D FORWARD -i $VPN_INTERFACE -o $CLIENT_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
iptables -I FORWARD 2 -i $VPN_INTERFACE -o $CLIENT_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

# === 8. MSS Clamping ===
iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# === 9. Full Tunnel (awg-server2) ===
if ip link show awg-server2 >/dev/null 2>&1; then
    echo "🛡️ Восстанавливаем правила для awg-server2..."
    iptables -t mangle -D PREROUTING -s 10.9.0.0/24 -j MARK --set-mark 0x2000 2>/dev/null
    iptables -t nat -D POSTROUTING -s 10.9.0.0/24 -o amnezia-client -j MASQUERADE 2>/dev/null
    iptables -D FORWARD -i awg-server2 -o amnezia-client -j ACCEPT 2>/dev/null
    iptables -D FORWARD -i amnezia-client -o awg-server2 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    
    iptables -t mangle -A PREROUTING -s 10.9.0.0/24 -j MARK --set-mark 0x2000
    iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -o amnezia-client -j MASQUERADE
    iptables -I FORWARD 1 -i awg-server2 -o amnezia-client -j ACCEPT
    iptables -I FORWARD 2 -i amnezia-client -o awg-server2 -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    ip rule del fwmark 0x2000 table 200 2>/dev/null || true
    ip rule add fwmark 0x2000 table 200
    echo "  ✅ awg-server2 восстановлен"
fi

echo -e "${GREEN}🎉 Правила раздельного туннелирования успешно обновлены.${NC}"
SCRIPT

chmod +x "$AMNEZIA_DIR/update-vpn-routes.sh"
log "✅ Скрипт update-vpn-routes.sh создан"