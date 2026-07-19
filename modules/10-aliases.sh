#!/bin/bash
# Модуль 10: Алиасы и команды

set -e

log() { echo -e "\033[0;36m[10-aliases]\033[0m $1"; }

log "📝 Настройка алиасов..."
cat >> /root/.bashrc << EOF

# ==============================================================================
# === AmneziaWG Gateway Aliases ===
# ==============================================================================
vpn-help() {
    local CYAN='\033[0;36m'; local GREEN='\033[0;32m'; local YELLOW='\033[1;33m'
    local NC='\033[0m'; local BOLD='\033[1m'
    
    echo ""
    echo -e "\${BOLD}\${CYAN}╔════════════════════════════════════════════════════════════════╗\${NC}"
    echo -e "\${BOLD}\${CYAN}║          📖 СПРАВКА ПО КОМАНДАМ AmneziaWG VPN                 ║\${NC}"
    echo -e "\${BOLD}\${CYAN}╚════════════════════════════════════════════════════════════════╝\${NC}"
    echo ""
    echo -e "\${BOLD}\${GREEN}🚀 ГЛАВНЫЕ КОМАНДЫ\${NC}"
    echo -e "  \${YELLOW}vpn-reload\${NC}        Полный цикл: списки → выбор сервера → правила"
    echo -e "  \${YELLOW}vpn-update\${NC}        Обновить правила маршрутизации"
    echo -e "  \${YELLOW}vpn-fast\${NC}          Быстрое обновление БЕЗ резолвинга"
    echo -e "  \${YELLOW}vpn-switch\${NC}        Переключиться на лучший сервер"
    echo ""
    echo -e "\${BOLD}\${GREEN}📊 СТАТУСЫ\${NC}"
    echo -e "  \${YELLOW}aws\${NC}               Статус обоих серверов (Split + Full)"
    echo -e "  \${YELLOW}awc\${NC}               Статус клиентского туннеля"
    echo -e "  \${YELLOW}awstatus\${NC}          Краткая сводка"
    echo ""
    echo -e "\${BOLD}\${GREEN}📥 СПИСКИ\${NC}"
    echo -e "  \${YELLOW}vpn-lists-update\${NC}  Запустить обновление списков"
    echo -e "  \${YELLOW}vpn-lists-status\${NC}  Статус таймера"
    echo -e "  \${YELLOW}vpn-stats\${NC}         Статистика записей"
    echo ""
    echo -e "\${BOLD}\${GREEN}🛡 WATCHDOG\${NC}"
    echo -e "  \${YELLOW}watchdog-status\${NC}   Статус таймера"
    echo -e "  \${YELLOW}watchdog-logs\${NC}     Логи Watchdog"
    echo ""
    echo -e "\${BOLD}\${GREEN}✏ РЕДАКТИРОВАНИЕ\${NC}"
    echo -e "  \${YELLOW}edit-vpn\${NC}          vpn-domains.conf"
    echo -e "  \${YELLOW}edit-direct\${NC}       vpn-outside.conf"
    echo -e "  \${YELLOW}edit-include-urls\${NC} Источники для VPN"
    echo -e "  \${YELLOW}edit-exclude-urls\${NC} Источники для Direct"
    echo -e "  \${YELLOW}edit-filter-urls\${NC}  Фильтры мусора"
    echo ""
}

alias help-vpn='vpn-help'
alias vpn-reload='/usr/local/bin/vpn-reload'
alias vpn-update='$AMNEZIA_DIR/update-vpn-routes.sh'
alias vpn-fast='$AMNEZIA_DIR/update-vpn-routes.sh --fast'
alias aws='echo -e "\n\033[1;32m=== 🟢 Сервер 1: Split (41820) ===\033[0m" && awg show awg-server 2>/dev/null && echo -e "\n\033[1;34m=== 🔵 Сервер 2: Full (41821) ===\033[0m" && awg show awg-server2 2>/dev/null'
alias aws1='awg show awg-server'
alias aws2='awg show awg-server2'
alias awc='awg show amnezia-client'
alias awstatus='echo -e "\n\033[1;33m=== 📊 КРАТКАЯ СВОДКА ===\033[0m" && echo -e "\n🟢 Сервер 1:" && awg show awg-server 2>/dev/null | grep -E "listening port:|endpoint:|latest handshake:|transfer:" && echo -e "\n🔵 Сервер 2:" && awg show awg-server2 2>/dev/null | grep -E "listening port:|endpoint:|latest handshake:|transfer:"'
alias vpn-switch='$AMNEZIA_DIR/switch-vpn.sh'
alias vpn-lists-update='$AMNEZIA_DIR/update-lists.sh'
alias vpn-lists-status='systemctl status amnezia-update-lists.timer --no-pager'
alias vpn-lists-logs='tail -n 50 $AMNEZIA_DIR/logs/update-lists.log'
alias vpn-stats='echo "📊 Статистика:" && echo "  vpn-domains.conf: \$(grep -cv "^#\|^\$" $AMNEZIA_DIR/vpn-domains.conf 2>/dev/null || echo 0) записей" && echo "  vpn-outside.conf: \$(grep -cv "^#\|^\$" $AMNEZIA_DIR/vpn-outside.conf 2>/dev/null || echo 0) записей"'
alias watchdog-status='systemctl status vpn-watchdog.timer vpn-watchdog-cascade.timer --no-pager 2>/dev/null'
alias watchdog-logs='tail -n 30 $AMNEZIA_DIR/logs/vpn-watchdog*.log 2>/dev/null'
alias edit-vpn='nano $AMNEZIA_DIR/vpn-domains.conf'
alias edit-direct='nano $AMNEZIA_DIR/vpn-outside.conf'
alias edit-include-urls='nano $AMNEZIA_DIR/include_urls.conf'
alias edit-include-custom='nano $AMNEZIA_DIR/include_custom.conf'
alias edit-exclude-urls='nano $AMNEZIA_DIR/exclude_urls.conf'
alias edit-exclude-custom='nano $AMNEZIA_DIR/exclude_custom.conf'
alias edit-filter-urls='nano $AMNEZIA_DIR/filter_urls.conf'
alias edit-filter-custom='nano $AMNEZIA_DIR/filter_custom.conf'
EOF

# Создание мастер-скрипта vpn-reload
cat > /usr/local/bin/vpn-reload << EOF
#!/bin/bash
CURRENT_USER=\$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/\$CURRENT_USER/amnezia"

echo "🔄 1. Обновление списков..."
\$AMNEZIA_DIR/update-lists.sh 2>/dev/null || echo "⚠️ Smart Update не установлен"

if [[ -f "\$AMNEZIA_DIR/switch-vpn.sh" ]]; then
    echo -e "\n📡 2. Выбор лучшего сервера..."
    \$AMNEZIA_DIR/switch-vpn.sh
fi

echo -e "\n🔁 3. Перезапуск VPN-клиента..."
systemctl restart awg-quick@amnezia-client 2>/dev/null || true

echo -e "\n🌐 4. Применение правил..."
\$AMNEZIA_DIR/update-vpn-routes.sh --fast

echo -e "\n✅ Готово!"
awg show amnezia-client 2>/dev/null | grep -E "endpoint:|latest handshake:|transfer:" || echo "⚠️ Туннель не активен"
EOF
chmod +x /usr/local/bin/vpn-reload

log "✅ Алиасы настроены. Используйте 'vpn-help' для справки"