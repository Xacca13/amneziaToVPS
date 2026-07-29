#!/bin/bash
# ==============================================================================
# 🚀 AmneziaWG Gateway — Интерактивный установщик (Cascade + dnsmasq)
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

get_public_ip() {
    echo -e "\n${BOLD}${CYAN}🌐 Укажите публичный IP этого VPS:${NC}"
    local detected_ip
    detected_ip=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || echo 'не удалось определить')
    echo -e "${YELLOW}💡 Подсказка: ${NC}${detected_ip}"
    
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
    local -