#!/bin/bash
# Модуль 06: Применение маршрутов (apply-routes.sh)

set -e

log() { echo -e "\033[0;36m[06-routes]\033[0m $1"; }

log "📝 Создание скрипта apply-routes.sh..."
cat > "$AMNEZIA_DIR/apply-routes.sh" << 'SCRIPT'
#!/bin/bash
# /home/user1/amnezia/apply-routes.sh
set -o pipefail

AMNEZIA_DIR="/home/$(logname 2>/dev/null || whoami)/amnezia"
VPN_CONF="$AMNEZIA_DIR/vpn-domains.conf"
DIRECT_CONF="$AMNEZIA_DIR/vpn-outside.conf"
DNSMASQ_SPLIT="/etc/dnsmasq.d/split-tunnel.conf"
ZAPRET_SYNC="$AMNEZIA_DIR/sync-vpn-domains-to-zapret.sh"

IPSET_VPN="vpn_routes"
IPSET_DIRECT="vpn_direct"
IPSET_VPN6="vpn_routes6"
IPSET_DIRECT6="vpn_direct6"

MARK_VPN="0x1000"
MARK_DIRECT="0x3000"
MARK_FULL="0x2000"

TABLE_VPN="100"
TABLE_FULL="200"

VPN_IF="amnezia-client"
SPLIT_IF="awg-server"
FULL_IF="awg-server2"
SPLIT_NET="10.8.0.0/24"
FULL_NET="10.9.0.0/24"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo "🔄 Применение маршрутов..."

# === 0. Ядро ===
grep -q "^100 " /etc/iproute2/rt_tables 2>/dev/null || echo "100 vpn_split" >> /etc/iproute2/rt_tables
grep -q "^200 " /etc/iproute2/rt_tables 2>/dev/null || echo "200 vpn_full" >> /etc/iproute2/rt_tables
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
sysctl -w net.ipv4.conf.all.rp_filter=2 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.rp_filter=2 >/dev/null 2>&1
for iface in /proc/sys/net/ipv4/conf/*/; do
    iface=$(basename "$iface")
    sysctl -w "net.ipv4.conf.$iface.rp_filter=2" >/dev/null 2>&1
done

# === 1. SSH защита ===
echo -e "${CYAN}🛡️ Защита SSH...${NC}"
SSH_IP=$(who am i 2>/dev/null | awk '{print $5}' | sed 's/(//;s/)//' | cut -d':' -f1)
[[ -n "$SSH_IP" && "$SSH_IP" != "tty" && "$SSH_IP" != ":0" ]] && echo "  SSH-клиент: $SSH_IP"

MAIN_IP=$(ip -4 addr show "$(ip route | awk '/default/{print $5; exit}')" 2>/dev/null | \
          grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
[[ -n "$MAIN_IP" ]] && echo "  Публичный IP: $MAIN_IP"

# === 2. ip rule ===
echo "📐 ip rule..."
if [[ -n "$SSH_IP" && "$SSH_IP" != "tty" && "$SSH_IP" != ":0" ]]; then
    ip rule del from all to "$SSH_IP/32" table main priority 1 2>/dev/null || true
    ip rule add from all to "$SSH_IP/32" table main priority 1
fi
for net in "$SPLIT_NET" "$FULL_NET" "127.0.0.0/8"; do
    ip rule del to "$net" table main priority 1 2>/dev/null || true
    ip rule add to "$net" table main priority 1
done
if [[ -n "$MAIN_IP" ]]; then
    ip rule del to "$MAIN_IP/32" table main priority 1 2>/dev/null || true
    ip rule add to "$MAIN_IP/32" table main priority 1
fi
ip rule del fwmark $MARK_FULL table $TABLE_FULL 2>/dev/null || true
ip rule add fwmark $MARK_FULL table $TABLE_FULL priority 2
ip rule del fwmark $MARK_VPN table $TABLE_VPN 2>/dev/null || true
ip rule add fwmark $MARK_VPN table $TABLE_VPN priority 3
ip rule del fwmark $MARK_DIRECT table main 2>/dev/null || true
ip rule add fwmark $MARK_DIRECT table main priority 4

# === 3. Таблицы маршрутизации ===
ip route flush table $TABLE_VPN 2>/dev/null || true
ip route flush table $TABLE_FULL 2>/dev/null || true
ip route add default dev $VPN_IF table $TABLE_VPN 2>/dev/null
ip route add default dev $VPN_IF table $TABLE_FULL 2>/dev/null

# === 4. iptables mangle — RETURN (защита) ===
echo -e "${CYAN}🛡️ iptables: RETURN-правила...${NC}"
for chain in PREROUTING OUTPUT; do
    for net in "127.0.0.0/8" "$SPLIT_NET" "$FULL_NET" "172.16.0.0/12" "192.168.0.0/16"; do
        iptables -t mangle -D "$chain" -d "$net" -j RETURN 2>/dev/null
    done
    [[ -n "$MAIN_IP" ]] && iptables -t mangle -D "$chain" -d "$MAIN_IP/32" -j RETURN 2>/dev/null
done

iptables -t mangle -I PREROUTING 1 -d 127.0.0.0/8 -j RETURN
iptables -t mangle -I PREROUTING 2 -d "$SPLIT_NET" -j RETURN
iptables -t mangle -I PREROUTING 3 -d "$FULL_NET" -j RETURN
iptables -t mangle -I PREROUTING 4 -d 172.16.0.0/12 -j RETURN
iptables -t mangle -I PREROUTING 5 -d 192.168.0.0/16 -j RETURN
[[ -n "$MAIN_IP" ]] && iptables -t mangle -I PREROUTING 6 -d "$MAIN_IP/32" -j RETURN

iptables -t mangle -I OUTPUT 1 -d 127.0.0.0/8 -j RETURN
iptables -t mangle -I OUTPUT 2 -d "$SPLIT_NET" -j RETURN
iptables -t mangle -I OUTPUT 3 -d "$FULL_NET" -j RETURN
iptables -t mangle -I OUTPUT 4 -d 172.16.0.0/12 -j RETURN
iptables -t mangle -I OUTPUT 5 -d 192.168.0.0/16 -j RETURN
[[ -n "$MAIN_IP" ]] && iptables -t mangle -I OUTPUT 6 -d "$MAIN_IP/32" -j RETURN

# === 5. Full Tunnel ===
iptables -t mangle -D PREROUTING -s "$FULL_NET" -j MARK --set-mark $MARK_FULL 2>/dev/null
iptables -t mangle -A PREROUTING -s "$FULL_NET" -j MARK --set-mark $MARK_FULL

# === 6. VPN-маркировка ===
iptables -t mangle -D PREROUTING -m set --match-set $IPSET_VPN dst -j MARK --set-mark $MARK_VPN 2>/dev/null
iptables -t mangle -D OUTPUT -m set --match-set $IPSET_VPN dst -j MARK --set-mark $MARK_VPN 2>/dev/null
iptables -t mangle -A PREROUTING -m set --match-set $IPSET_VPN dst -j MARK --set-mark $MARK_VPN
iptables -t mangle -A OUTPUT -m set --match-set $IPSET_VPN dst -j MARK --set-mark $MARK_VPN

# === 7. Direct-маркировка ===
iptables -t mangle -D PREROUTING -m set --match-set $IPSET_DIRECT dst ! -s "$FULL_NET" -j MARK --set-mark $MARK_DIRECT 2>/dev/null
iptables -t mangle -D OUTPUT -m set --match-set $IPSET_DIRECT dst ! -s "$FULL_NET" -j MARK --set-mark $MARK_DIRECT 2>/dev/null
iptables -t mangle -A PREROUTING -m set --match-set $IPSET_DIRECT dst ! -s "$FULL_NET" -j MARK --set-mark $MARK_DIRECT
iptables -t mangle -A OUTPUT -m set --match-set $IPSET_DIRECT dst ! -s "$FULL_NET" -j MARK --set-mark $MARK_DIRECT

# === 8. IPv6 ===
ip6tables -t mangle -D PREROUTING -m set --match-set $IPSET_VPN6 dst -j MARK --set-mark $MARK_VPN 2>/dev/null
ip6tables -t mangle -A PREROUTING -m set --match-set $IPSET_VPN6 dst -j MARK --set-mark $MARK_VPN
ip6tables -t mangle -D PREROUTING -m set --match-set $IPSET_DIRECT6 dst -j MARK --set-mark $MARK_DIRECT 2>/dev/null
ip6tables -t mangle -A PREROUTING -m set --match-set $IPSET_DIRECT6 dst -j MARK --set-mark $MARK_DIRECT

# === 9. NAT ===
ETH_IF=$(ip route | awk '/default/{print $5; exit}')
iptables -t nat -D POSTROUTING -o $VPN_IF -j MASQUERADE 2>/dev/null
iptables -t nat -A POSTROUTING -o $VPN_IF -j MASQUERADE
[[ -n "$ETH_IF" ]] && {
    iptables -t nat -D POSTROUTING -s "$SPLIT_NET" -o "$ETH_IF" -j MASQUERADE 2>/dev/null
    iptables -t nat -A POSTROUTING -s "$SPLIT_NET" -o "$ETH_IF" -j MASQUERADE
}
iptables -t nat -D POSTROUTING -s "$FULL_NET" -o $VPN_IF -j MASQUERADE 2>/dev/null
iptables -t nat -A POSTROUTING -s "$FULL_NET" -o $VPN_IF -j MASQUERADE

# === 10. FORWARD ===
iptables -D FORWARD -i $SPLIT_IF -o $VPN_IF -j ACCEPT 2>/dev/null
iptables -I FORWARD 1 -i $SPLIT_IF -o $VPN_IF -j ACCEPT
iptables -D FORWARD -i $VPN_IF -o $SPLIT_IF -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
iptables -I FORWARD 2 -i $VPN_IF -o $SPLIT_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
[[ -n "$ETH_IF" ]] && {
    iptables -D FORWARD -i $SPLIT_IF -o "$ETH_IF" -j ACCEPT 2>/dev/null
    iptables -I FORWARD 3 -i $SPLIT_IF -o "$ETH_IF" -j ACCEPT
    iptables -D FORWARD -i "$ETH_IF" -o $SPLIT_IF -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -I FORWARD 4 -i "$ETH_IF" -o $SPLIT_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
}
if ip link show $FULL_IF &>/dev/null; then
    iptables -D FORWARD -i $FULL_IF -o $VPN_IF -j ACCEPT 2>/dev/null
    iptables -I FORWARD 5 -i $FULL_IF -o $VPN_IF -j ACCEPT
    iptables -D FORWARD -i $VPN_IF -o $FULL_IF -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -I FORWARD 6 -i $VPN_IF -o $FULL_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
fi

# === 11. MSS ===
iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# === 12. DNS intercept → AdGuard Home ===
AGH_IP="127.0.0.1"
for iface in $SPLIT_IF $FULL_IF; do
    ip link show "$iface" &>/dev/null || continue
    for proto in udp tcp; do
        iptables -t nat -D PREROUTING -i "$iface" -p "$proto" --dport 53 -j DNAT --to-destination "${AGH_IP}:53" 2>/dev/null
        iptables -t nat -A PREROUTING -i "$iface" -p "$proto" --dport 53 -j DNAT --to-destination "${AGH_IP}:53"
    done
done

# === 13. dnsmasq ipset-правила ===
echo "📝 Генерация $DNSMASQ_SPLIT ..."
generate_rules() {
    local conf="$1" set4="$2" set6="$3"
    [[ -f "$conf" ]] || return
    sed 's/#.*//' "$conf" | tr -d '\r' | sed '/^[[:space:]]*$/d' | \
    grep -E '^[a-zA-Z0-9]' | \
    grep -vE '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]+)?$' | \
    grep -viE '^[0-9a-f]*:[0-9a-f:]+(/[0-9]+)?$' | \
    while IFS= read -r domain; do
        echo "ipset=/${domain}/${set4},${set6}"
    done
}
{
    echo "# Auto-generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    generate_rules "$VPN_CONF" "$IPSET_VPN" "$IPSET_VPN6"
    echo ""
    generate_rules "$DIRECT_CONF" "$IPSET_DIRECT" "$IPSET_DIRECT6"
} > "$DNSMASQ_SPLIT"
rules_count=$(grep -c "^ipset=" "$DNSMASQ_SPLIT" 2>/dev/null || echo 0)
echo -e "  ${GREEN}✅ dnsmasq: $rules_count правил${NC}"

# === 14. ipset: статические IP/CIDR ===
echo "📌 ipset: статические IP/CIDR..."
for set in $IPSET_VPN $IPSET_DIRECT; do
    ipset list "$set" &>/dev/null || ipset create "$set" hash:net family inet hashsize 4096 maxelem 524288
done
for set in $IPSET_VPN6 $IPSET_DIRECT6; do
    ipset list "$set" &>/dev/null || ipset create "$set" hash:net family inet6 hashsize 4096 maxelem 524288
done

add_static() {
    local conf="$1" set4="$2" set6="$3" cnt=0
    [[ -f "$conf" ]] || return
    while IFS= read -r ip; do
        ipset add "$set4" "$ip" -exist 2>/dev/null && ((cnt++))
    done < <(sed 's/#.*//' "$conf" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]+)?$')
    while IFS= read -r ip; do
        ipset add "$set6" "$ip" -exist 2>/dev/null && ((cnt++))
    done < <(sed 's/#.*//' "$conf" | grep -Ei '^[0-9a-f:]+(/[0-9]+)?$')
    echo "  $set4 + $set6: $cnt"
}
add_static "$VPN_CONF" "$IPSET_VPN" "$IPSET_VPN6"
add_static "$DIRECT_CONF" "$IPSET_DIRECT" "$IPSET_DIRECT6"

# === 15. Перезапуск dnsmasq ===
systemctl restart dnsmasq 2>/dev/null
sleep 1
if systemctl is-active dnsmasq &>/dev/null; then
    echo -e "  ${GREEN}✅ dnsmasq активен${NC}"
else
    echo -e "  ${RED}❌ dnsmasq не запустился! journalctl -u dnsmasq -n 20${NC}"
fi

# === 16. Zapret ===
if [[ -d "/opt/zapret2" ]]; then
    echo "🔄 Zapret: синхронизация..."
    if [[ -x "$ZAPRET_SYNC" ]]; then
        "$ZAPRET_SYNC" 2>&1 | tail -5
    else
        ZAPRET_HOSTLIST="/opt/zapret2/ipset/zapret-hosts-user.txt"
        ZAPRET_IPLIST="/opt/zapret2/ipset/zapret-ip-user.txt"
        if [[ -d "/opt/zapret2/ipset" ]]; then
            sed 's/#.*//' "$VPN_CONF" 2>/dev/null | grep -E '^[a-zA-Z0-9]' | \
            grep -vE '^([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -viE '^[0-9a-f]*:' | \
            LC_ALL=C sort -u > "$ZAPRET_HOSTLIST"
            { sed 's/#.*//' "$VPN_CONF" 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]+)?$'
              sed 's/#.*//' "$VPN_CONF" 2>/dev/null | grep -Ei '^[0-9a-f:]+(/[0-9]+)?$'
            } | LC_ALL=C sort -u > "$ZAPRET_IPLIST"
            [[ -x /opt/zapret2/ipset/create_ipset.sh ]] && /opt/zapret2/ipset/create_ipset.sh 2>/dev/null
            echo -e "  ${GREEN}✅ Zapret: hosts=$(wc -l < "$ZAPRET_HOSTLIST" | tr -d ' ') ip=$(wc -l < "$ZAPRET_IPLIST" | tr -d ' ')${NC}"
        fi
    fi
fi

# === 17. Диагностика ===
echo ""
echo -e "${CYAN}📋 Итог:${NC}"
for set in $IPSET_VPN $IPSET_DIRECT $IPSET_VPN6 $IPSET_DIRECT6; do
    cnt=$(ipset list "$set" 2>/dev/null | grep -c "^[0-9a-f]" || echo 0)
    printf "  %-16s %s\n" "$set" "$cnt"
done
echo "  dnsmasq правил: $rules_count"
echo ""
echo -e "${GREEN}🎉 Маршрутизация применена.${NC}"
SCRIPT
chmod +x "$AMNEZIA_DIR/apply-routes.sh"
log "✅ Скрипт apply-routes.sh создан (dnsmasq + ipset + защита SSH)"