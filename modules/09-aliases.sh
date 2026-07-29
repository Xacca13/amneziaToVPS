#!/bin/bash
# Модуль 09: Алиасы и команды
set -e
log() { echo -e "\033[0;36m[09-aliases]\033[0m $1"; }

log "📝 Настройка алиасов..."
cat >> /root/.bashrc << 'EOF'
# ==============================================================================
# === AmneziaWG Gateway Aliases (Cascade + dnsmasq) ===
# ==============================================================================
vpn-help() {
    local C='\033[0;36m'; local G='\033[0;32m'; local Y='\033[1;33m'; local N='\033[0m'; local B='\033[1m'
    echo ""
    echo -e "${B}${C}╔══════════════════════════════════════════════════════════╗${N}"
    echo -e "${B}${C}║       📖 СПРАВКА ПО КОМАНДАМ AmneziaWG VPN             ║${N}"
    echo -e "${B}${C}╚══════════════════════════════════════════════════════════╝${N}"
    echo ""
    echo -e "${B}${G}🚀 ГЛАВНЫЕ${N}"
    echo -e "  ${Y}vpn-reload${N}         Полный цикл: списки + маршруты + dnsmasq"
    echo -e "  ${Y}vpn-apply${N}          Только применить маршруты (apply-routes)"
    echo -e "  ${Y}vpn-lists${N}          Только обновить списки (без маршрутов)"
    echo ""
    echo -e "${B}${G}📊 СТАТУСЫ${N}"
    echo -e "  ${Y}aws${N}                Статус обоих серверов (Split + Full)"
    echo -e "  ${Y}awc${N}                Статус клиентского туннеля"
    echo -e "  ${Y}vpn-stats${N}          Статистика записей в конфигах"
    echo -e "  ${Y}ipset-stats${N}        Статистика ipset (зарезолвленные IP)"
    echo ""
    echo -e "${B}${G}🔄 СЕРВИСЫ${N}"
    echo -e "  ${Y}dnsmasq-restart${N}    Перезапуск dnsmasq"
    echo -e "  ${Y}dnsmasq-log${N}        Лог dnsmasq"
    echo -e "  ${Y}watchdog-status${N}    Статус watchdog"
    echo -e "  ${Y}watchdog-logs${N}      Логи watchdog"
    echo ""
    echo -e "${B}${G}🛡 ZAPRET${N}"
    echo -e "  ${Y}zapret-sync${N}        Синхронизация списков с Zapret"
    echo -e "  ${Y}zapret-start${N}       Запуск Zapret"
    echo -e "  ${Y}zapret-stop${N}        Остановка Zapret"
    echo -e "  ${Y}zapret-restart${N}     Перезапуск Zapret"
    echo ""
    echo -e "${B}${G}✏ РЕДАКТИРОВАНИЕ${N}"
    echo -e "  ${Y}edit-vpn${N}           vpn-domains.conf (VPN-список)"
    echo -e "  ${Y}edit-direct${N}        vpn-outside.conf (Direct-список)"
    echo -e "  ${Y}edit-include${N}       include_urls.conf (источники VPN)"
    echo -e "  ${Y}edit-exclude${N}       exclude_urls.conf (источники Direct)"
    echo ""
}
alias help-vpn='vpn-help'
alias vpn-reload='/usr/local/bin/vpn-reload'
alias vpn-apply='$(logname 2>/dev/null || echo user1 | xargs -I{} echo /home/{}/amnezia)/apply-routes.sh 2>/dev/null || /home/user1/amnezia/apply-routes.sh'
alias vpn-lists='$(logname 2>/dev/null || echo user1 | xargs -I{} echo /home/{}/amnezia)/update-lists.sh 2>/dev/null || /home/user1/amnezia/update-lists.sh'
alias aws='echo -e "\n\033[1;32m=== 🟢 Split (41820) ===\033[0m" && awg show awg-server 2>/dev/null; echo -e "\n\033[1;34m=== 🔵 Full (41821) ===\033[0m" && awg show awg-server2 2>/dev/null'
alias aws1='awg show awg-server'
alias aws2='awg show awg-server2'
alias awc='awg show amnezia-client'
alias vpn-stats='AMNEZIA_DIR="/home/$(logname 2>/dev/null || whoami)/amnezia"; echo "📊 Статистика:"; echo "  vpn-domains.conf: $(grep -cvE "^#|^$" "$AMNEZIA_DIR/vpn-domains.conf" 2>/dev/null || echo 0)"; echo "  vpn-outside.conf: $(grep -cvE "^#|^$" "$AMNEZIA_DIR/vpn-outside.conf" 2>/dev/null || echo 0)"'
alias ipset-stats='echo "📊 ipset:"; for s in vpn_routes vpn_direct vpn_routes6 vpn_direct6; do echo "  $s: $(ipset list "$s" 2>/dev/null | grep -c "^[0-9a-f]" || echo 0)"; done'
alias dnsmasq-restart='systemctl restart dnsmasq && echo "✅ dnsmasq перезапущен"'
alias dnsmasq-log='journalctl -u dnsmasq -n 50 --no-pager'
alias watchdog-status='systemctl status vpn-watchdog-cascade.timer --no-pager 2>/dev/null'
alias watchdog-logs='tail -n 30 /home/$(logname 2>/dev/null || whoami)/amnezia/logs/vpn-watchdog*.log 2>/dev/null'
alias edit-vpn='nano /home/$(logname 2>/dev/null || whoami)/amnezia/vpn-domains.conf'
alias edit-direct='nano /home/$(logname 2>/dev/null || whoami)/amnezia/vpn-outside.conf'
alias edit-include='nano /home/$(logname 2>/dev/null || whoami)/amnezia/include_urls.conf'
alias edit-exclude='nano /home/$(logname 2>/dev/null || whoami)/amnezia/exclude_urls.conf'
alias zapret-sync='/home/$(logname 2>/dev/null || whoami)/amnezia/sync-vpn-domains-to-zapret.sh'
alias zapret-start='systemctl start zapret2 2>/dev/null || /opt/zapret2/init.d/sysv/zapret start'
alias zapret-stop='systemctl stop zapret2 2>/dev/null || /opt/zapret2/init.d/sysv/zapret stop'
alias zapret-restart='systemctl restart zapret2 2>/dev/null || /opt/zapret2/init.d/sysv/zapret restart'
EOF

cat > /usr/local/bin/vpn-reload << 'RELOAD'
#!/bin/bash
AMNEZIA_DIR="/home/$(logname 2>/dev/null || whoami)/amnezia"
echo "🔄 1. Обновление списков..."
"$AMNEZIA_DIR/update-lists.sh" 2>/dev/null || echo "⚠️ update-lists.sh не найден"
echo ""
echo "🌐 2. Применение маршрутов..."
"$AMNEZIA_DIR/apply-routes.sh"
echo ""
echo "✅ Готово!"
awg show amnezia-client 2>/dev/null | grep -E "endpoint:|latest handshake:|transfer:" || echo "⚠️ Туннель не активен"
RELOAD
chmod +x /usr/local/bin/vpn-reload

log "✅ Алиасы настроены. Используйте 'vpn-help' для справки"