#!/bin/bash
# ==============================================================================
# 🚀 AmneziaWG Gateway — Интерактивный установщик (Только Каскад + dnsmasq)
# ==============================================================================
set -e

REPO_URL="https://raw.githubusercontent.com/Xacca13/amneziaToVPS/main"
MODULES_URL="$REPO_URL/modules"
CONFIGS_URL="$REPO_URL/configs/urls"
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"
INSTALL_LOG="/var/log/amnezia-gateway-install.log"
TEMP_DIR="/tmp/amnezia-gateway-install"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'
BOLD='\033[1m'

log() { echo -e "$1" | tee -a "$INSTALL_LOG"; }
log_success() { log "${GREEN}✅ $1${NC}"; }
log_error()   { log "${RED}❌ $1${NC}"; }
log_warning() { log "${YELLOW}⚠️  $1${NC}"; }
log_info()    { log "${CYAN}ℹ️  $1${NC}"; }

print_banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║       🛡️  AmneziaWG Gateway — Каскад VPS-to-VPS               ║"
    echo "║          🐧 CentOS 9 Stream (dnsmasq + ipset)                  ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен от имени root!"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/centos-release ]]; then
        log_warning "Этот установщик оптимизирован для CentOS 9 Stream."
        read -p "Продолжить? (y/n): " CONFIRM_OS
        echo
        [[ ! "$CONFIRM_OS" =~ ^[Yy]$ ]] && exit 1
    fi
}

download_module() {
    local module_name="$1"
    local target_path="$TEMP_DIR/modules/$module_name"
    log_info "📥 Скачивание модуля: $module_name"
    mkdir -p "$(dirname "$target_path")"
    if curl -sSL --fail "$MODULES_URL/$module_name" -o "$target_path" 2>/dev/null; then
        chmod +x "$target_path"
        log_success "Модуль скачан: $module_name"
        return 0
    else
        log_error "Не удалось скачать модуль: $module_name"
        return 1
    fi
}

download_list_file() {
    local file_name="$1"
    local target_path="$TEMP_DIR/configs/$file_name"
    mkdir -p "$(dirname "$target_path")"
    if curl -sSL --fail "$CONFIGS_URL/$file_name" -o "$target_path" 2>/dev/null; then
        return 0
    else
        log_warning "Не удалось скачать список: $file_name"
        return 1
    fi
}

get_public_ip() {
    echo -e "\n${BOLD}${CYAN}🌐 Укажите публичный IP этого VPS:${NC}"
    local detected_ip
    detected_ip=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || echo 'не удалось определить')
    echo -e "${YELLOW}💡 Подсказка: ${NC}${detected_ip}"
    
    # Безопасный ввод без вложенных $()
    read -p "${CYAN}IP: ${NC}" PUBLIC_IP
    [[ -z "$PUBLIC_IP" ]] && { log_error "IP не может быть пустым!"; exit 1; }
    log_success "Публичный IP: $PUBLIC_IP"
}

select_local_servers() {
    echo -e "\n${BOLD}${CYAN}📶 ШАГ 1. Какие локальные серверы запустить?${NC}"
    echo -e "  ${YELLOW}1)${NC} ✅ Split (41820) + Full (41821)"
    echo -e "  ${YELLOW}2)${NC} ✅ Только Split (41820)"
    echo -e "  ${YELLOW}3)${NC} ✅ Только Full (41821)"
    echo -e "  ${YELLOW}4)${NC} ⚪ Без локальных серверов (только клиент)"
    
    read -p "${CYAN}Ваш выбор [1-4]: ${NC}" LOCAL_SERVERS
    case "$LOCAL_SERVERS" in
        1) INSTALL_SPLIT=1; INSTALL_FULL=1 ;;
        2) INSTALL_SPLIT=1; INSTALL_FULL=0 ;;
        3) INSTALL_SPLIT=0; INSTALL_FULL=1 ;;
        4) INSTALL_SPLIT=0; INSTALL_FULL=0 ;;
        *) log_error "Неверный выбор"; exit 1 ;;
    esac
    log_success "Split: $INSTALL_SPLIT | Full: $INSTALL_FULL"
}

select_clients_count() {
    echo -e "\n${BOLD}${CYAN}👥 ШАГ 1.1. Количество клиентских конфигов:${NC}"
    echo -e "${YELLOW}💡 Сколько конфигураций клиентов сгенерировать для выбранных серверов?${NC}"
    
    read -p "${CYAN}Введите число (по умолчанию 5, макс. 50): ${NC}" INPUT_COUNT
    if [[ -z "$INPUT_COUNT" ]]; then
        CLIENT_COUNT=5
    elif [[ "$INPUT_COUNT" =~ ^[0-9]+$ ]] && [[ "$INPUT_COUNT" -ge 1 ]] && [[ "$INPUT_COUNT" -le 50 ]]; then
        CLIENT_COUNT=$INPUT_COUNT
    else
        log_warning "Неверный ввод. Будет использовано значение по умолчанию: 5"
        CLIENT_COUNT=5
    fi
    log_success "Будет сгенерировано клиентских конфигов: $CLIENT_COUNT"
}

select_optional() {
    echo -e "\n${BOLD}${CYAN}🧩 ШАГ 2. Опциональные компоненты:${NC}"
    
    # Безопасный ввод без вложенных $()
    read -p "${CYAN}🛡️  Установить AdGuard Home (DNS-фильтр + upstream для dnsmasq)? [y/n]: ${NC}" OPT_ADGUARD
    read -p "${CYAN}⚡ Установить Zapret (обход DPI)? [y/n]: ${NC}" OPT_ZAPRET
    read -p "${CYAN}🖥️  Установить Веб-панель управления (Dashboard)? [y/n]: ${NC}" OPT_DASHBOARD

    [[ "$OPT_ADGUARD" =~ ^[Yy] ]] && INSTALL_ADGUARD=1 || INSTALL_ADGUARD=0
    [[ "$OPT_ZAPRET" =~ ^[Yy] ]] && INSTALL_ZAPRET=1 || INSTALL_ZAPRET=0
    [[ "$OPT_DASHBOARD" =~ ^[Yy] ]] && INSTALL_DASHBOARD=1 || INSTALL_DASHBOARD=0

    log_success "AdGuard: $INSTALL_ADGUARD | Zapret: $INSTALL_ZAPRET | Dashboard: $INSTALL_DASHBOARD"
}

present_url_menu() {
    local list_file="$1"
    local output_file="$2"
    local category_name="$3"

    echo -e "\n${BOLD}${CYAN}📋 Выбор источников для: ${category_name}${NC}"
    echo -e "${YELLOW}Введите номера через пробел (например: 1 3 5) или 'all' для всех.${NC}"
    echo ""

    local index=1
    local -a urls=()
    local -a descs=()

    while IFS='|' read -r desc url || [[ -n "$url" ]]; do
        desc=$(echo "$desc" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        url=$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$url" || "$desc" =~ ^# ]] && continue
        descs+=("$desc")
        urls+=("$url")
        echo -e "  ${YELLOW}${index})${NC} ${desc}"
        ((index++))
    done < "$list_file"

    local skip_index=$index
    echo -e "  ${YELLOW}${skip_index})${NC} ⚪ Пропустить"
    echo ""
    read -p "${CYAN}Ваш выбор: ${NC}" selection

    echo "# === Источники для ${category_name} ===" > "$output_file"
    echo "# Сгенерировано $(date '+%Y-%m-%d %H:%M:%S')" >> "$output_file"

    if [[ "$selection" == "all" || "$selection" == "a" || "$selection" == "A" ]]; then
        for url in "${urls[@]}"; do
            echo "$url" >> "$output_file"
        done
        log_success "Выбраны все источники для ${category_name} (${#urls[@]} шт.)"
    elif [[ "$selection" == "$skip_index" || "$selection" == "0" ]]; then
        echo "# (Пусто — добавьте вручную в *_custom.conf)" >> "$output_file"
        log_info "Источники для ${category_name} пропущены"
    else
        local added=0
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -lt $skip_index ]]; then
                echo "${urls[$((num-1))]}" >> "$output_file"
                ((added++))
            fi
        done
        if [[ $added -gt 0 ]]; then
            log_success "Добавлено $added источников для ${category_name}"
        else
            echo "# (Пусто — добавьте вручную в *_custom.conf)" >> "$output_file"
            log_info "Источники для ${category_name} пропущены"
        fi
    fi
}

select_urls_interactive() {
    echo -e "\n${BOLD}${CYAN}📋 ШАГ 3. Настройка списков маршрутизации:${NC}"
    echo -e "${YELLOW}💡 Загрузка актуальных списков из репозитория...${NC}"
    echo -e "${YELLOW}💡 Фильтрация рекламы/казино/фишинга теперь через AdGuard Home.${NC}"

    download_list_file "include-urls.list" || { log_error "Не удалось загрузить include-urls.list"; exit 1; }
    download_list_file "exclude-urls.list" || { log_error "Не удалось загрузить exclude-urls.list"; exit 1; }

    mkdir -p "$AMNEZIA_DIR"

    present_url_menu "$TEMP_DIR/configs/include-urls.list" "$AMNEZIA_DIR/include_urls.conf" "VPN (через туннель)"
    present_url_menu "$TEMP_DIR/configs/exclude-urls.list" "$AMNEZIA_DIR/exclude_urls.conf" "Direct (напрямую)"

    cat > "$AMNEZIA_DIR/include_custom.conf" << 'EOF'
# === Пользовательские домены и IP для VPN ===
# Формат: домен, IPv4, IPv4/CIDR, IPv6
# Примеры:
#   youtube.com
#   142.250.0.0/15
#   2001:db8::/32
EOF

    cat > "$AMNEZIA_DIR/exclude_custom.conf" << 'EOF'
# === Пользовательские домены и IP для Direct ===
# Формат: домен, IPv4, IPv4/CIDR, IPv6
# Примеры:
#   sberbank.ru
#   yandex.ru
#   10.0.0.0/8
EOF

    chown "$CURRENT_USER:$CURRENT_USER" "$AMNEZIA_DIR"/*.conf 2>/dev/null || true
    log_success "Конфиги списков сгенерированы"
}

setup_cascade_config() {
    echo -e "\n${BOLD}${CYAN}🌉 Настройка каскада VPS-to-VPS:${NC}"
    
    # Безопасный ввод без вложенных $()
    read -p "${CYAN}IP VPS_B (сервер-выход): ${NC}" VPS_B_IP
    read -p "${CYAN}Порт VPS_B [41820]: ${NC}" VPS_B_PORT
    VPS_B_PORT=${VPS_B_PORT:-41820}
    
    log_warning "⚠️  Вам потребуется вручную создать конфиг каскада после установки."
    log_info "📝 Команда: ${YELLOW}nano /etc/amnezia/amneziawg/amnezia-client.conf${NC}"
    log_info "📝 Endpoint: ${CYAN}${VPS_B_IP}:${VPS_B_PORT}${NC}"
    
    # Безопасный ввод y/n (без флага -n 1, чтобы корректно съесть Enter)
    read -p "Продолжить установку? (y/n): " CONFIRM_CASCADE
    echo
    [[ ! "$CONFIRM_CASCADE" =~ ^[Yy]$ ]] && exit 1
}

show_summary() {
    echo -e "\n${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}                    📋 СВОДКА УСТАНОВКИ                          ${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}Режим:${NC}            🌉 Каскад VPS-to-VPS (dnsmasq + ipset)"
    echo -e "  ${BOLD}Публичный IP:${NC}     $PUBLIC_IP"
    echo -e "  ${BOLD}Split Tunnel:${NC}     $( [[ $INSTALL_SPLIT -eq 1 ]] && echo '✅ Да (41820)' || echo '❌ Нет' )"
    echo -e "  ${BOLD}Full Tunnel:${NC}      $( [[ $INSTALL_FULL -eq 1 ]] && echo '✅ Да (41821)' || echo '❌ Нет' )"
    echo -e "  ${BOLD}Клиентских конф.:${NC}  $CLIENT_COUNT"
    echo -e "  ${BOLD}AdGuard Home:${NC}     $( [[ $INSTALL_ADGUARD -eq 1 ]] && echo '✅ Да' || echo '❌ Нет' )"
    echo -e "  ${BOLD}Zapret:${NC}           $( [[ $INSTALL_ZAPRET -eq 1 ]] && echo '✅ Да' || echo '❌ Нет' )"
    echo -e "  ${BOLD}Dashboard:${NC}        $( [[ $INSTALL_DASHBOARD -eq 1 ]] && echo '✅ Да' || echo '❌ Нет' )"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    
    # Безопасный ввод y/n (без флага -n 1)
    read -p "${YELLOW}Начать установку? [y/n]: ${NC}" CONFIRM_INSTALL
    echo
    [[ ! "$CONFIRM_INSTALL" =~ ^[Yy]$ ]] && { log_info "Установка отменена"; exit 0; }
}

main() {
    check_root
    check_os
    mkdir -p "$TEMP_DIR/modules" "$TEMP_DIR/configs"
    mkdir -p "$AMNEZIA_DIR"/{clients,server-clients,server-clients-full,lists,logs}
    > "$INSTALL_LOG"
    print_banner

    get_public_ip
    select_local_servers
    select_clients_count
    select_optional
    select_urls_interactive
    setup_cascade_config
    show_summary

    echo -e "\n${BOLD}${CYAN}📥 Скачивание модулей из GitHub...${NC}"

    # ТОЛЬКО необходимые модули для каскада (мульти-конфиги удалены)
    MANDATORY_MODULES=(
        "00-base-system.sh"
        "01-amneziawg.sh"
        "04-client-cascade.sh"
        "05-lists-manager.sh"
        "06-routes-updater.sh"
        "09-aliases.sh"
        "10-zapret-sync.sh"
    )
    [[ $INSTALL_SPLIT -eq 1 ]] && MANDATORY_MODULES+=("02-server-split.sh")
    [[ $INSTALL_FULL -eq 1 ]] && MANDATORY_MODULES+=("03-server-full.sh")
    [[ $INSTALL_ADGUARD -eq 1 ]] && MANDATORY_MODULES+=("07-adguard.sh")
    [[ $INSTALL_ZAPRET -eq 1 ]] && MANDATORY_MODULES+=("08-zapret.sh")
    [[ $INSTALL_DASHBOARD -eq 1 ]] && MANDATORY_MODULES+=("11-dashboard.sh")

    for module in "${MANDATORY_MODULES[@]}"; do
        download_module "$module" || { log_error "Критическая ошибка: $module"; exit 1; }
    done

    echo -e "\n${BOLD}${CYAN}⚙️  Выполнение модулей...${NC}\n"
    export PUBLIC_IP AMNEZIA_DIR CURRENT_USER INSTALL_LOG CLIENT_COUNT

    log_info "🔧 Модуль 00: Базовая подготовка системы"
    bash "$TEMP_DIR/modules/00-base-system.sh" 2>&1 | tee -a "$INSTALL_LOG"

    log_info "🔧 Модуль 01: Установка AmneziaWG"
    bash "$TEMP_DIR/modules/01-amneziawg.sh" 2>&1 | tee -a "$INSTALL_LOG"

    [[ $INSTALL_SPLIT -eq 1 ]] && {
        log_info "🔧 Модуль 02: Split Tunneling сервер"
        bash "$TEMP_DIR/modules/02-server-split.sh" 2>&1 | tee -a "$INSTALL_LOG"
    }
    [[ $INSTALL_FULL -eq 1 ]] && {
        log_info "🔧 Модуль 03: Full Tunnel сервер"
        bash "$TEMP_DIR/modules/03-server-full.sh" 2>&1 | tee -a "$INSTALL_LOG"
    }

    log_info "🔧 Модуль 04: Клиент для каскада"
    bash "$TEMP_DIR/modules/04-client-cascade.sh" 2>&1 | tee -a "$INSTALL_LOG"

    log_info "🔧 Модуль 05: Менеджер списков (update-lists.sh)"
    bash "$TEMP_DIR/modules/05-lists-manager.sh" 2>&1 | tee -a "$INSTALL_LOG"

    log_info "🔧 Модуль 06: Применение маршрутов (apply-routes.sh)"
    bash "$TEMP_DIR/modules/06-routes-updater.sh" 2>&1 | tee -a "$INSTALL_LOG"

    [[ $INSTALL_ADGUARD -eq 1 ]] && {
        log_info "🔧 Модуль 07: AdGuard Home"
        bash "$TEMP_DIR/modules/07-adguard.sh" 2>&1 | tee -a "$INSTALL_LOG"
    }
    [[ $INSTALL_ZAPRET -eq 1 ]] && {
        log_info "🔧 Модуль 08: Zapret 2"
        bash "$TEMP_DIR/modules/08-zapret.sh" 2>&1 | tee -a "$INSTALL_LOG"
    }

    log_info "🔧 Модуль 09: Алиасы и команды"
    bash "$TEMP_DIR/modules/09-aliases.sh" 2>&1 | tee -a "$INSTALL_LOG"

    log_info "🔧 Модуль 10: Синхронизация с Zapret"
    bash "$TEMP_DIR/modules/10-zapret-sync.sh" 2>&1 | tee -a "$INSTALL_LOG" || true

    [[ $INSTALL_DASHBOARD -eq 1 ]] && {
        log_info "🔧 Модуль 11: Веб-панель управления"
        bash "$TEMP_DIR/modules/11-dashboard.sh" 2>&1 | tee -a "$INSTALL_LOG"
    }

    log_info "🔧 Финальная настройка..."
    bash "$AMNEZIA_DIR/update-lists.sh" 2>&1 | tee -a "$INSTALL_LOG" || true
    bash "$AMNEZIA_DIR/apply-routes.sh" 2>&1 | tee -a "$INSTALL_LOG" || true

    rm -rf "$TEMP_DIR"

    echo -e "\n${BOLD}${GREEN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    🎉 УСТАНОВКА ЗАВЕРШЕНА!                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "\n${BOLD}${CYAN}📋 Следующие шаги:${NC}"
    echo -e "  ${YELLOW}1.${NC} Создайте конфиг: ${CYAN}nano /etc/amnezia/amneziawg/amnezia-client.conf${NC}"
    echo -e "  ${YELLOW}2.${NC} Запустите: ${GREEN}systemctl start awg-quick@amnezia-client${NC}"
    echo -e "  ${YELLOW}3.${NC} Примените правила: ${GREEN}vpn-reload${NC}"
    [[ $INSTALL_SPLIT -eq 1 ]] && echo -e "  ${YELLOW}4.${NC} Split конфиги: ${CYAN}$AMNEZIA_DIR/server-clients/${NC}"
    [[ $INSTALL_FULL -eq 1 ]] && echo -e "  ${YELLOW}5.${NC} Full конфиги: ${CYAN}$AMNEZIA_DIR/server-clients-full/${NC}"
    [[ $INSTALL_ADGUARD -eq 1 ]] && echo -e "  ${YELLOW}6.${NC} AdGuard Home: ${CYAN}http://$PUBLIC_IP:3000${NC}"
    echo -e "       ${YELLOW}⚠️  В настройках DNS укажите Upstream: ${CYAN}127.0.0.1:5353${NC}"
    [[ $INSTALL_DASHBOARD -eq 1 ]] && echo -e "  ${YELLOW}7.${NC} Dashboard: ${CYAN}http://10.8.0.1:8501${NC} (только через VPN!)"
    echo -e "\n${BOLD}📖 Справка:${NC} ${GREEN}vpn-help${NC}  |  ${BOLD}📝 Лог:${NC} ${CYAN}$INSTALL_LOG${NC}\n"
}

main "$@"