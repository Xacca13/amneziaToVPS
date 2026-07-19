#!/bin/bash
# ==============================================================================
# 🚀 AmneziaWG Gateway — Интерактивный установщик
# ==============================================================================

set -e

# ==============================================================================
# КОНСТАНТЫ
# ==============================================================================
REPO_URL="https://raw.githubusercontent.com/Xacca13/amnezia-gateway/main"
MODULES_URL="$REPO_URL/modules"
CONFIGS_URL="$REPO_URL/configs/urls"

CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"
INSTALL_LOG="/var/log/amnezia-gateway-install.log"
TEMP_DIR="/tmp/amnezia-gateway-install"

# Цвета
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'
BOLD='\033[1m'

# ==============================================================================
# ФУНКЦИИ
# ==============================================================================
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
    echo "║         🛡️  AmneziaWG Gateway — Модульный установщик           ║"
    echo "║                🐧 CentOS 9 Stream (Dynamic URLs)               ║"
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
        read -p "Продолжить? (y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
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

# ==============================================================================
# ИНТЕРАКТИВНОЕ МЕНЮ
# ==============================================================================
select_mode() {
    echo -e "\n${BOLD}${CYAN}📡 ШАГ 1. Выберите режим работы VPS:${NC}"
    echo -e "  ${YELLOW}1)${NC} 📦 ${BOLD}Мульти-конфиги${NC} (Автопереключение, тест скорости)"
    echo -e "  ${YELLOW}2)${NC} 🌉 ${BOLD}Каскад VPS-to-VPS${NC} (Один статичный конфиг, упрощенный Watchdog)"
    read -p "$(echo -e ${CYAN}Ваш выбор [1/2]:${NC} )" MODE
    case "$MODE" in
        1) MODE_NAME="multi"; log_success "Выбран режим: Мульти-конфиги" ;;
        2) MODE_NAME="cascade"; log_success "Выбран режим: Каскад VPS-to-VPS" ;;
        *) log_error "Неверный выбор"; exit 1 ;;
    esac
}

get_public_ip() {
    echo -e "\n${BOLD}${CYAN}🌐 Укажите публичный IP этого VPS:${NC}"
    echo -e "${YELLOW}💡 Подсказка: ${NC}$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || echo 'не удалось определить')"
    read -p "$(echo -e ${CYAN}IP:${NC} )" PUBLIC_IP
    [[ -z "$PUBLIC_IP" ]] && { log_error "IP не может быть пустым!"; exit 1; }
    log_success "Публичный IP: $PUBLIC_IP"
}

select_local_servers() {
    echo -e "\n${BOLD}${CYAN}📶 ШАГ 2. Какие локальные серверы запустить?${NC}"
    echo -e "  ${YELLOW}1)${NC} ✅ Split (41820) + Full (41821)"
    echo -e "  ${YELLOW}2)${NC} ✅ Только Split (41820)"
    echo -e "  ${YELLOW}3)${NC} ✅ Только Full (41821)"
    echo -e "  ${YELLOW}4)${NC} ⚪ Без локальных серверов (только клиент)"
    read -p "$(echo -e ${CYAN}Ваш выбор [1-4]:${NC} )" LOCAL_SERVERS
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
    echo -e "\n${BOLD}${CYAN}👥 ШАГ 2.1. Количество клиентских конфигов:${NC}"
    echo -e "${YELLOW}💡 Сколько конфигураций клиентов сгенерировать для выбранных серверов?${NC}"
    read -p "$(echo -e ${CYAN}Введите число (по умолчанию 5, макс. 50):${NC} )" INPUT_COUNT
    
    # Валидация ввода
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
    echo -e "\n${BOLD}${CYAN}🧩 ШАГ 3. Опциональные компоненты:${NC}"
    read -p "$(echo -e ${CYAN}🧠 Установить Smart Update (автообновление списков)? [y/n]:${NC} )" OPT_SMART
    read -p "$(echo -e ${CYAN}🛡️  Установить AdGuard Home (DNS-фильтр)? [y/n]:${NC} )" OPT_ADGUARD
    read -p "$(echo -e ${CYAN}⚡ Установить Zapret (обход DPI)? [y/n]:${NC} )" OPT_ZAPRET
    
    [[ "$OPT_SMART" =~ ^[Yy] ]] && INSTALL_SMART=1 || INSTALL_SMART=0
    [[ "$OPT_ADGUARD" =~ ^[Yy] ]] && INSTALL_ADGUARD=1 || INSTALL_ADGUARD=0
    [[ "$OPT_ZAPRET" =~ ^[Yy] ]] && INSTALL_ZAPRET=1 || INSTALL_ZAPRET=0
    log_success "Smart Update: $INSTALL_SMART | AdGuard: $INSTALL_ADGUARD | Zapret: $INSTALL_ZAPRET"
}

present_url_menu() {
    local list_file="$1"
    local output_file="$2"
    local category_name="$3"
    
    echo -e "\n${BOLD}${CYAN}📋 Выбор источников для: ${category_name}${NC}"
    echo -e "${YELLOW}Введите номера через пробел (например: 1 3 5) или 'all' для выбора всех.${NC}"
    echo ""
    
    local index=1
    local -a urls=()
    local -a descs=()
    
    # Читаем файл, игнорируя комментарии и пустые строки
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
    echo -e "  ${YELLOW}${skip_index})${NC} ⚪ Пропустить (оставить пустым для ручного заполнения)"
    echo ""
    
    read -p "$(echo -e ${CYAN}Ваш выбор:${NC} )" selection
    
    echo "# === Источники для ${category_name} ===" > "$output_file"
    echo "# Сгенерировано интерактивным установщиком $(date '+%Y-%m-%d %H:%M:%S')" >> "$output_file"
    
    if [[ "$selection" == "all" || "$selection" == "a" || "$selection" == "A" ]]; then
        for url in "${urls[@]}"; do
            echo "$url" >> "$output_file"
        done
        log_success "Выбраны все источники для ${category_name} (${#urls[@]} шт.)"
    elif [[ "$selection" == "$skip_index" || "$selection" == "0" ]]; then
        echo "# (Пусто - добавьте вручную в соответствующий *_custom.conf)" >> "$output_file"
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
            echo "# (Пусто - добавьте вручную в соответствующий *_custom.conf)" >> "$output_file"
            log_info "Источники для ${category_name} пропущены (неверный ввод)"
        fi
    fi
}

select_urls_interactive() {
    echo -e "\n${BOLD}${CYAN}📋 ШАГ 4. Настройка списков маршрутизации:${NC}"
    echo -e "${YELLOW}💡 Загрузка актуальных списков из репозитория...${NC}"
    
    # Скачиваем списки из репозитория
    download_list_file "include-urls.list" || { log_error "Критическая ошибка загрузки include-urls.list"; exit 1; }
    download_list_file "exclude-urls.list" || { log_error "Критическая ошибка загрузки exclude-urls.list"; exit 1; }
    download_list_file "filter-urls.list" || { log_error "Критическая ошибка загрузки filter-urls.list"; exit 1; }
    
    mkdir -p "$AMNEZIA_DIR"
    
    # Запускаем интерактивное меню для каждой категории
    present_url_menu "$TEMP_DIR/configs/include-urls.list" "$AMNEZIA_DIR/include_urls.conf" "VPN (через туннель)"
    present_url_menu "$TEMP_DIR/configs/exclude-urls.list" "$AMNEZIA_DIR/exclude_urls.conf" "Direct (напрямую)"
    present_url_menu "$TEMP_DIR/configs/filter-urls.list" "$AMNEZIA_DIR/filter_urls.conf" "Глобальные фильтры (мусор)"
    
    # Создаем файлы для ручного добавления
    cat > "$AMNEZIA_DIR/include_custom.conf" << 'EOF'
# === Пользовательские домены и IP для VPN ===
# Добавьте сюда то, чего нет в автоматических списках
# youtube.com
# telegram.org
EOF
    
    cat > "$AMNEZIA_DIR/exclude_custom.conf" << 'EOF'
# === Пользовательские домены и IP для Direct ===
# sberbank.ru
# yandex.ru
# 10.0.0.0/8
EOF
    
    cat > "$AMNEZIA_DIR/filter_custom.conf" << 'EOF'
# === Ручной список мусора/мертвых доменов ===
# 0001.hdbaza.net
EOF
    
    chown "$CURRENT_USER:$CURRENT_USER" "$AMNEZIA_DIR"/*urls.conf "$AMNEZIA_DIR"/*custom.conf 2>/dev/null || true
    log_success "Конфиги списков успешно сгенерированы"
}

setup_cascade_config() {
    if [[ "$MODE_NAME" == "cascade" ]]; then
        echo -e "\n${BOLD}${CYAN}🌉 Настройка каскада VPS-to-VPS:${NC}"
        read -p "$(echo -e ${CYAN}IP VPS_B (сервер-выход):${NC} )" VPS_B_IP
        read -p "$(echo -e ${CYAN}Порт VPS_B [41820]:${NC} )" VPS_B_PORT
        VPS_B_PORT=${VPS_B_PORT:-41820}
        
        log_warning "⚠️  Вам потребуется вручную создать конфиг каскада после установки."
        log_info "📝 Команда: ${YELLOW}nano /etc/amnezia/amneziawg/amnezia-client.conf${NC}"
        log_info "📝 Endpoint должен быть: ${CYAN}${VPS_B_IP}:${VPS_B_PORT}${NC}"
        read -p "Продолжить установку? (y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
}

show_summary() {
    echo -e "\n${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}                    📋 СВОДКА УСТАНОВКИ                          ${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}Режим:${NC}            $( [[ $MODE_NAME == 'multi' ]] && echo '📦 Мульти-конфиги' || echo '🌉 Каскад VPS-to-VPS' )"
    echo -e "  ${BOLD}Публичный IP:${NC}     $PUBLIC_IP"
    echo -e "  ${BOLD}Split Tunnel:${NC}     $( [[ $INSTALL_SPLIT -eq 1 ]] && echo '✅ Да (порт 41820)' || echo '❌ Нет' )"
    echo -e "  ${BOLD}Full Tunnel:${NC}      $( [[ $INSTALL_FULL -eq 1 ]] && echo '✅ Да (порт 41821)' || echo '❌ Нет' )"
    echo -e "  ${BOLD}Smart Update:${NC}     $( [[ $INSTALL_SMART -eq 1 ]] && echo '✅ Да' || echo '❌ Нет' )"
    echo -e "  ${BOLD}AdGuard Home:${NC}     $( [[ $INSTALL_ADGUARD -eq 1 ]] && echo '✅ Да' || echo '❌ Нет' )"
    echo -e "  ${BOLD}Zapret:${NC}           $( [[ $INSTALL_ZAPRET -eq 1 ]] && echo '✅ Да' || echo '❌ Нет' )"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    read -p "$(echo -e ${YELLOW}Начать установку? [y/n]:${NC} )" -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "Установка отменена"; exit 0; }
}

# ==============================================================================
# ОСНОВНОЙ ПРОЦЕСС УСТАНОВКИ
# ==============================================================================
main() {
    check_root
    check_os
    
    mkdir -p "$TEMP_DIR/modules" "$TEMP_DIR/configs"
    mkdir -p "$AMNEZIA_DIR"/{clients,server-clients,server-clients-full,lists,logs}
    > "$INSTALL_LOG"
    
    print_banner
    
    select_mode
    get_public_ip
    select_local_servers
    select_clients_count
    select_optional
    select_urls_interactive
    setup_cascade_config
    show_summary
    
    echo -e "\n${BOLD}${CYAN}📥 Скачивание модулей из GitHub...${NC}"
    
    MANDATORY_MODULES=("00-base-system.sh" "01-amneziawg.sh" "07-routes-updater.sh")
    [[ $INSTALL_SPLIT -eq 1 ]] && MANDATORY_MODULES+=("02-server-split.sh")
    [[ $INSTALL_FULL -eq 1 ]] && MANDATORY_MODULES+=("03-server-full.sh")
    [[ "$MODE_NAME" == "multi" ]] && MANDATORY_MODULES+=("04-client-multi.sh") || MANDATORY_MODULES+=("05-client-cascade.sh")
    [[ $INSTALL_SMART -eq 1 ]] && MANDATORY_MODULES+=("06-lists-manager.sh")
    [[ $INSTALL_ADGUARD -eq 1 ]] && MANDATORY_MODULES+=("08-adguard.sh")
    [[ $INSTALL_ZAPRET -eq 1 ]] && MANDATORY_MODULES+=("09-zapret.sh")
    MANDATORY_MODULES+=("10-aliases.sh")
    
    for module in "${MANDATORY_MODULES[@]}"; do
        download_module "$module" || { log_error "Критическая ошибка: не удалось скачать $module"; exit 1; }
    done
    
    echo -e "\n${BOLD}${CYAN}⚙️  Выполнение модулей...${NC}\n"
    export PUBLIC_IP MODE_NAME AMNEZIA_DIR CURRENT_USER INSTALL_LOG
    
    log_info "🔧 Модуль 00: Базовая подготовка системы"
    bash "$TEMP_DIR/modules/00-base-system.sh" 2>&1 | tee -a "$INSTALL_LOG"
    
    log_info "🔧 Модуль 01: Установка AmneziaWG"
    bash "$TEMP_DIR/modules/01-amneziawg.sh" 2>&1 | tee -a "$INSTALL_LOG"
    
    [[ $INSTALL_SPLIT -eq 1 ]] && { log_info "🔧 Модуль 02: Split Tunneling сервер"; bash "$TEMP_DIR/modules/02-server-split.sh" 2>&1 | tee -a "$INSTALL_LOG"; }
    [[ $INSTALL_FULL -eq 1 ]] && { log_info "🔧 Модуль 03: Full Tunnel сервер"; bash "$TEMP_DIR/modules/03-server-full.sh" 2>&1 | tee -a "$INSTALL_LOG"; }
    
    if [[ "$MODE_NAME" == "multi" ]]; then
        log_info "🔧 Модуль 04: Клиент с автопереключением"
        bash "$TEMP_DIR/modules/04-client-multi.sh" 2>&1 | tee -a "$INSTALL_LOG"
    else
        log_info "🔧 Модуль 05: Клиент для каскада"
        bash "$TEMP_DIR/modules/05-client-cascade.sh" 2>&1 | tee -a "$INSTALL_LOG"
    fi
    
    [[ $INSTALL_SMART -eq 1 ]] && { log_info "🔧 Модуль 06: Smart Update v2.0"; bash "$TEMP_DIR/modules/06-lists-manager.sh" 2>&1 | tee -a "$INSTALL_LOG"; }
    
    log_info "🔧 Модуль 07: Обновление маршрутов"
    bash "$TEMP_DIR/modules/07-routes-updater.sh" 2>&1 | tee -a "$INSTALL_LOG"
    
    [[ $INSTALL_ADGUARD -eq 1 ]] && { log_info "🔧 Модуль 08: AdGuard Home"; bash "$TEMP_DIR/modules/08-adguard.sh" 2>&1 | tee -a "$INSTALL_LOG"; }
    [[ $INSTALL_ZAPRET -eq 1 ]] && { log_info "🔧 Модуль 09: Zapret 2"; bash "$TEMP_DIR/modules/09-zapret.sh" 2>&1 | tee -a "$INSTALL_LOG"; }
    
    log_info "🔧 Модуль 10: Алиасы и команды"
    bash "$TEMP_DIR/modules/10-aliases.sh" 2>&1 | tee -a "$INSTALL_LOG"
    
    log_info "🔧 Финальная настройка..."
    [[ $INSTALL_SMART -eq 1 ]] && bash "$AMNEZIA_DIR/update-lists.sh" 2>&1 | tee -a "$INSTALL_LOG" || true
    bash "$AMNEZIA_DIR/update-vpn-routes.sh" 2>&1 | tee -a "$INSTALL_LOG" || true
    
    rm -rf "$TEMP_DIR"
    
    echo -e "\n${BOLD}${GREEN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    🎉 УСТАНОВКА ЗАВЕРШЕНА!                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${BOLD}${CYAN}📋 Следующие шаги:${NC}"
    if [[ "$MODE_NAME" == "multi" ]]; then
        echo -e "  ${YELLOW}1.${NC} Загрузите конфиги провайдеров в: ${CYAN}$AMNEZIA_DIR/clients/${NC}"
        echo -e "  ${YELLOW}2.${NC} ⚠️  В каждом .conf: ${RED}Удалите${NC} ${CYAN}DNS = ...${NC} и ${GREEN}Добавьте${NC} ${CYAN}Table = off${NC}"
        echo -e "  ${YELLOW}3.${NC} Запустите: ${GREEN}vpn-reload${NC}"
    else
        echo -e "  ${YELLOW}1.${NC} Создайте конфиг: ${CYAN}nano /etc/amnezia/amneziawg/amnezia-client.conf${NC}"
        echo -e "  ${YELLOW}2.${NC} Запустите: ${GREEN}systemctl start awg-quick@amnezia-client${NC}"
        echo -e "  ${YELLOW}3.${NC} Примените правила: ${GREEN}vpn-update${NC}"
    fi
    
    [[ $INSTALL_SPLIT -eq 1 ]] && echo -e "  ${YELLOW}4.${NC} Split конфиг: ${CYAN}$AMNEZIA_DIR/server-clients/client_01.conf${NC}"
    [[ $INSTALL_FULL -eq 1 ]] && echo -e "  ${YELLOW}5.${NC} Full конфиг: ${CYAN}$AMNEZIA_DIR/server-clients-full/client_01.conf${NC}"
    [[ $INSTALL_ADGUARD -eq 1 ]] && echo -e "  ${YELLOW}6.${NC} AdGuard Home: ${CYAN}http://$PUBLIC_IP:3000${NC} (закройте порт 3000 после настройки!)"
    
    echo -e "\n  ${BOLD}📖 Справка:${NC} ${GREEN}vpn-help${NC}  |  ${BOLD}📝 Лог:${NC} ${CYAN}$INSTALL_LOG${NC}\n"
}

main "$@"