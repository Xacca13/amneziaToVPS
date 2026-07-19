#!/bin/bash
# ==============================================================================
# 🚀 AmneziaWG Gateway — Интерактивный установщик
# ==============================================================================
# Использование:
#   curl -sSL https://raw.githubusercontent.com/Xacca13/amnezia-gateway/main/install.sh | bash
#   или
#   ./install.sh
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
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; NC='\033[0m'
BOLD='\033[1m'

# ==============================================================================
# ФУНКЦИИ
# ==============================================================================
log() {
    echo -e "$1" | tee -a "$INSTALL_LOG"
}

log_success() { log "${GREEN}✅ $1${NC}"; }
log_error()   { log "${RED}❌ $1${NC}"; }
log_warning() { log "${YELLOW}⚠️  $1${NC}"; }
log_info()    { log "${CYAN}ℹ️  $1${NC}"; }

print_banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║     🛡️  AmneziaWG Gateway — Модульный установщик              ║"
    echo "║     📦 Версия: 2.0 | 🐧 CentOS 9 Stream                      ║"
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
        log_warning "На других системах могут возникнуть проблемы."
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

download_config() {
    local config_name="$1"
    local target_path="$TEMP_DIR/configs/$config_name"
    
    mkdir -p "$(dirname "$target_path")"
    if curl -sSL --fail "$CONFIGS_URL/$config_name" -o "$target_path" 2>/dev/null; then
        return 0
    else
        log_warning "Не удалось скачать конфиг: $config_name"
        return 1
    fi
}

# ==============================================================================
# ИНТЕРАКТИВНОЕ МЕНЮ
# ==============================================================================
select_mode() {
    echo -e "\n${BOLD}${CYAN}📡 ШАГ 1. Выберите режим работы VPS:${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} 📦 ${BOLD}Мульти-конфиги${NC}"
    echo "     └─ Автопереключение между провайдерами, тест скорости"
    echo "     └─ Watchdog с исключением сбойных конфигов"
    echo ""
    echo -e "  ${YELLOW}2)${NC} 🌉 ${BOLD}Каскад VPS-to-VPS${NC}"
    echo "     └─ Один статичный конфиг к другому VPS"
    echo "     └─ Упрощенный Watchdog (рестарт туннеля)"
    echo ""
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
    
    if [[ -z "$PUBLIC_IP" ]]; then
        log_error "IP не может быть пустым!"
        exit 1
    fi
    
    if ! [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_warning "IP не соответствует формату IPv4. Продолжаем с указанным значением."
    fi
    
    log_success "Публичный IP: $PUBLIC_IP"
}

select_local_servers() {
    echo -e "\n${BOLD}${CYAN}📶 ШАГ 2. Какие локальные серверы запустить?${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} ✅ Split Tunneling (порт 41820) + Full Tunnel (порт 41821)"
    echo -e "  ${YELLOW}2)${NC} ✅ Только Split Tunneling (порт 41820)"
    echo -e "  ${YELLOW}3)${NC} ✅ Только Full Tunnel (порт 41821)"
    echo -e "  ${YELLOW}4)${NC} ⚪ Без локальных серверов (только клиент)"
    echo ""
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

select_optional() {
    echo -e "\n${BOLD}${CYAN}🧩 ШАГ 3. Опциональные компоненты:${NC}"
    echo ""
    read -p "$(echo -e ${CYAN}🧠 Установить Smart Update (автообновление списков)? [y/n]:${NC} )" OPT_SMART
    read -p "$(echo -e ${CYAN}🛡️  Установить AdGuard Home (DNS-фильтр)? [y/n]:${NC} )" OPT_ADGUARD
    read -p "$(echo -e ${CYAN}⚡ Установить Zapret (обход DPI)? [y/n]:${NC} )" OPT_ZAPRET
    
    [[ "$OPT_SMART" =~ ^[Yy] ]] && INSTALL_SMART=1 || INSTALL_SMART=0
    [[ "$OPT_ADGUARD" =~ ^[Yy] ]] && INSTALL_ADGUARD=1 || INSTALL_ADGUARD=0
    [[ "$OPT_ZAPRET" =~ ^[Yy] ]] && INSTALL_ZAPRET=1 || INSTALL_ZAPRET=0
    
    log_success "Smart Update: $INSTALL_SMART | AdGuard: $INSTALL_ADGUARD | Zapret: $INSTALL_ZAPRET"
}

select_urls_interactive() {
    echo -e "\n${BOLD}${CYAN}📋 ШАГ 4. Настройка списков маршрутизации:${NC}"
    echo ""
    echo -e "${YELLOW}💡 Вы можете выбрать готовые наборы или настроить вручную.${NC}"
    echo ""
    
    # === VPN (через туннель) ===
    echo -e "${BOLD}${BLUE}📥 Источники для VPN (через туннель):${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} ✅ Antifilter + Re-filter (основные блокировки РФ)"
    echo -e "  ${YELLOW}2)${NC} ✅ GubernievS (Roblox/WhatsApp/Google/Akamai/Cloudflare)"
    echo -e "  ${YELLOW}3)${NC} ✅ Itdoginfo Services (Meta/Twitter/TikTok/YouTube)"
    echo -e "  ${YELLOW}4)${NC} ✅ Itdoginfo Subnets (IPv4/IPv6 подсети)"
    echo -e "  ${YELLOW}5)${NC} 📦 Всё вышеперечисленное (полный набор)"
    echo -e "  ${YELLOW}6)${NC} ⚪ Пропустить (использовать только ручные списки)"
    echo ""
    read -p "$(echo -e ${CYAN}Ваш выбор [1-6]:${NC} )" VPN_PRESET
    
    # === Direct (напрямую) ===
    echo ""
    echo -e "${BOLD}${BLUE}📤 Источники для Direct (напрямую):${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} ✅ AntiZapret exclude-hosts.txt"
    echo -e "  ${YELLOW}2)${NC} ✅ Itdoginfo outside-kvas.lst (российские ресурсы)"
    echo -e "  ${YELLOW}3)${NC} 📦 Оба набора"
    echo -e "  ${YELLOW}4)${NC} ⚪ Пропустить"
    echo ""
    read -p "$(echo -e ${CYAN}Ваш выбор [1-4]:${NC} )" DIRECT_PRESET
    
    # === Фильтры (мусор) ===
    echo ""
    echo -e "${BOLD}${BLUE}🗑️ Глобальные фильтры (очистка мусора):${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} ✅ AntiZapret remove-hosts (мертвые домены)"
    echo -e "  ${YELLOW}2)${NC} ✅ OISD Big + NSFW (глобальный мусор)"
    echo -e "  ${YELLOW}3)${NC} ✅ AdGuard SDNS + StevenBlack + HaGeZi"
    echo -e "  ${YELLOW}4)${NC} 📦 Все фильтры (максимальная очистка)"
    echo -e "  ${YELLOW}5)${NC} ⚪ Пропустить фильтрацию"
    echo ""
    read -p "$(echo -e ${CYAN}Ваш выбор [1-5]:${NC} )" FILTER_PRESET
    
    # === Генерация конфигов на основе выбора ===
    generate_urls_configs
}

generate_urls_configs() {
    mkdir -p "$AMNEZIA_DIR"
    
    # === include_urls.conf (для VPN) ===
    cat > "$AMNEZIA_DIR/include_urls.conf" << 'EOF'
# === Источники для VPN (через туннель) ===
# Сгенерировано интерактивным установщиком
EOF
    
    case "$VPN_PRESET" in
        1)
            cat >> "$AMNEZIA_DIR/include_urls.conf" << 'EOF'
https://github.com/bol-van/rulist/refs/heads/main/reestr_hostname.txt
https://github.com/1andrevich/Re-filter-lists/releases/latest/download/domains_all.lst
https://github.com/1andrevich/Re-filter-lists/releases/latest/download/ipsum.lst
https://github.com/1andrevich/Re-filter-lists/raw/refs/heads/main/community.lst
https://github.com/1andrevich/Re-filter-lists/raw/refs/heads/main/community_ips.lst
EOF
            ;;
        2)
            cat >> "$AMNEZIA_DIR/include_urls.conf" << 'EOF'
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/roblox-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/whatsapp-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/akamai-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/google-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/telegram-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/ovh-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/digitalocean-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/hetzner-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/amazon-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/cloudflare-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/discord-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/fastly-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-hosts.txt
EOF
            ;;
        3)
            cat >> "$AMNEZIA_DIR/include_urls.conf" << 'EOF'
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/twitter.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/tiktok.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/youtube.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/telegram.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/roblox.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/google_ai.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/google_meet.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/google_play.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/hdrezka.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/cloudflare.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/cloudfront.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/digitalocean.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/hetzner.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/ovh.lst
EOF
            ;;
        4)
            cat >> "$AMNEZIA_DIR/include_urls.conf" << 'EOF'
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/Discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/Meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/Twitter.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/cloudflare.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/cloudfront.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/digitalocean.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/google_meet.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/hetzner.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/ovh.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/roblox.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/telegram.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/twitter.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/Discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/Meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/Twitter.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/cloudflare.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/cloudfront.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/digitalocean.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/google_meet.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/hetzner.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/ovh.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/telegram.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/twitter.lst
EOF
            ;;
        5)
            # Полный набор — объединяем все
            VPN_PRESET=1; generate_urls_vpn_1
            VPN_PRESET=2; generate_urls_vpn_2
            VPN_PRESET=3; generate_urls_vpn_3
            VPN_PRESET=4; generate_urls_vpn_4
            # Дедупликация
            sort -u "$AMNEZIA_DIR/include_urls.conf" -o "$AMNEZIA_DIR/include_urls.conf.tmp"
            grep -v "^#" "$AMNEZIA_DIR/include_urls.conf.tmp" > "$AMNEZIA_DIR/include_urls.conf.urls"
            grep "^#" "$AMNEZIA_DIR/include_urls.conf" > "$AMNEZIA_DIR/include_urls.conf.header"
            cat "$AMNEZIA_DIR/include_urls.conf.header" "$AMNEZIA_DIR/include_urls.conf.urls" > "$AMNEZIA_DIR/include_urls.conf"
            rm -f "$AMNEZIA_DIR/include_urls.conf.tmp" "$AMNEZIA_DIR/include_urls.conf.urls" "$AMNEZIA_DIR/include_urls.conf.header"
            ;;
        6)
            log_info "Пропускаем автоматические списки VPN"
            ;;
    esac
    
    # === exclude_urls.conf (для Direct) ===
    cat > "$AMNEZIA_DIR/exclude_urls.conf" << 'EOF'
# === Источники для Direct (напрямую) ===
# Сгенерировано интерактивным установщиком
EOF
    
    case "$DIRECT_PRESET" in
        1)
            echo "https://github.com/GubernievS/AntiZapret-VPN/raw/refs/heads/main/setup/root/antizapret/download/exclude-hosts.txt" >> "$AMNEZIA_DIR/exclude_urls.conf"
            ;;
        2)
            cat >> "$AMNEZIA_DIR/exclude_urls.conf" << 'EOF'
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/outside-kvas.lst
EOF
            ;;
        3)
            cat >> "$AMNEZIA_DIR/exclude_urls.conf" << 'EOF'
https://github.com/GubernievS/AntiZapret-VPN/raw/refs/heads/main/setup/root/antizapret/download/exclude-hosts.txt
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/outside-kvas.lst
EOF
            ;;
        4)
            log_info "Пропускаем автоматические списки Direct"
            ;;
    esac
    
    # === filter_urls.conf (мусор) ===
    cat > "$AMNEZIA_DIR/filter_urls.conf" << 'EOF'
# === Глобальные фильтры (очистка мусора) ===
# Сгенерировано интерактивным установщиком
EOF
    
    case "$FILTER_PRESET" in
        1)
            cat >> "$AMNEZIA_DIR/filter_urls.conf" << 'EOF'
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/remove-hosts.txt.gz
EOF
            ;;
        2)
            cat >> "$AMNEZIA_DIR/filter_urls.conf" << 'EOF'
https://github.com/sjhgvr/oisd/raw/refs/heads/main/domainswild2_big.txt
https://raw.githubusercontent.com/sjhgvr/oisd/refs/heads/main/domainswild2_big.txt
https://raw.githubusercontent.com/sjhgvr/oisd/refs/heads/main/domainswild2_nsfw.txt
https://github.com/sjhgvr/oisd/raw/refs/heads/main/domainswild2_nsfw.txt
EOF
            ;;
        3)
            cat >> "$AMNEZIA_DIR/filter_urls.conf" << 'EOF'
https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-only/hosts
https://nsfw.oisd.nl
https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/nsfw-onlydomains.txt
https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/gambling-onlydomains.txt
https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/fake-onlydomains.txt
EOF
            ;;
        4)
            # Все фильтры
            FILTER_PRESET=1; generate_urls_filter_1
            FILTER_PRESET=2; generate_urls_filter_2
            FILTER_PRESET=3; generate_urls_filter_3
            sort -u "$AMNEZIA_DIR/filter_urls.conf" -o "$AMNEZIA_DIR/filter_urls.conf.tmp"
            grep -v "^#" "$AMNEZIA_DIR/filter_urls.conf.tmp" > "$AMNEZIA_DIR/filter_urls.conf.urls"
            grep "^#" "$AMNEZIA_DIR/filter_urls.conf" > "$AMNEZIA_DIR/filter_urls.conf.header"
            cat "$AMNEZIA_DIR/filter_urls.conf.header" "$AMNEZIA_DIR/filter_urls.conf.urls" > "$AMNEZIA_DIR/filter_urls.conf"
            rm -f "$AMNEZIA_DIR/filter_urls.conf.tmp" "$AMNEZIA_DIR/filter_urls.conf.urls" "$AMNEZIA_DIR/filter_urls.conf.header"
            ;;
        5)
            log_info "Пропускаем глобальные фильтры"
            ;;
    esac
    
    # === Custom файлы (ручные списки) ===
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
# 192.168.0.0/16
EOF
    
    cat > "$AMNEZIA_DIR/filter_custom.conf" << 'EOF'
# === Ручной список мусора/мертвых доменов ===
# 0001.hdbaza.net
# 00024.ru
EOF
    
    chown "$CURRENT_USER:$CURRENT_USER" "$AMNEZIA_DIR"/*urls.conf "$AMNEZIA_DIR"/*custom.conf 2>/dev/null || true
    
    log_success "Конфиги списков сгенерированы"
}

# Вспомогательные функции для генерации (используются в preset 5 и 4)
generate_urls_vpn_1() {
    cat >> "$AMNEZIA_DIR/include_urls.conf" << 'EOF'
https://github.com/bol-van/rulist/refs/heads/main/reestr_hostname.txt
https://github.com/1andrevich/Re-filter-lists/releases/latest/download/domains_all.lst
https://github.com/1andrevich/Re-filter-lists/releases/latest/download/ipsum.lst
https://github.com/1andrevich/Re-filter-lists/raw/refs/heads/main/community.lst
https://github.com/1andrevich/Re-filter-lists/raw/refs/heads/main/community_ips.lst
EOF
}

generate_urls_vpn_2() {
    cat >> "$AMNEZIA_DIR/include_urls.conf" << 'EOF'
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/roblox-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/whatsapp-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/akamai-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/google-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/telegram-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/cloudflare-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/discord-ips.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-hosts.txt
EOF
}

generate_urls_vpn_3() {
    cat >> "$AMNEZIA_DIR/include_urls.conf" << 'EOF'
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/twitter.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/tiktok.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/youtube.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/telegram.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/roblox.lst
EOF
}

generate_urls_vpn_4() {
    cat >> "$AMNEZIA_DIR/include_urls.conf" << 'EOF'
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/Discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/Meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/Twitter.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv4/cloudflare.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/Discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/Meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/Twitter.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Subnets/IPv6/cloudflare.lst
EOF
}

generate_urls_filter_1() {
    cat >> "$AMNEZIA_DIR/filter_urls.conf" << 'EOF'
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/remove-hosts.txt.gz
EOF
}

generate_urls_filter_2() {
    cat >> "$AMNEZIA_DIR/filter_urls.conf" << 'EOF'
https://github.com/sjhgvr/oisd/raw/refs/heads/main/domainswild2_big.txt
https://raw.githubusercontent.com/sjhgvr/oisd/refs/heads/main/domainswild2_nsfw.txt
EOF
}

generate_urls_filter_3() {
    cat >> "$AMNEZIA_DIR/filter_urls.conf" << 'EOF'
https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-only/hosts
https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/nsfw-onlydomains.txt
https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/gambling-onlydomains.txt
https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/fake-onlydomains.txt
EOF
}

# ==============================================================================
# ПОДГОТОВКА КОНФИГА КАСКАДА
# ==============================================================================
setup_cascade_config() {
    if [[ "$MODE_NAME" == "cascade" ]]; then
        echo -e "\n${BOLD}${CYAN}🌉 Настройка каскада VPS-to-VPS:${NC}"
        echo ""
        read -p "$(echo -e ${CYAN}IP VPS_B (сервер-выход):${NC} )" VPS_B_IP
        read -p "$(echo -e ${CYAN}Порт VPS_B [41820]:${NC} )" VPS_B_PORT
        VPS_B_PORT=${VPS_B_PORT:-41820}
        
        echo ""
        log_warning "⚠️  Вам потребуется вручную создать конфиг каскада."
        log_info "📝 После установки выполните:"
        echo ""
        echo -e "  ${YELLOW}nano /etc/amnezia/amneziawg/amnezia-client.conf${NC}"
        echo ""
        echo -e "И вставьте туда конфиг с параметрами:"
        echo -e "  ${CYAN}Endpoint = ${VPS_B_IP}:${VPS_B_PORT}${NC}"
        echo ""
        read -p "Продолжить установку? (y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
}

# ==============================================================================
# СВОДКА И ПОДТВЕРЖДЕНИЕ
# ==============================================================================
show_summary() {
    echo -e "\n${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}                    📋 СВОДКА УСТАНОВКИ                          ${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Режим:${NC}            $( [[ $MODE_NAME == 'multi' ]] && echo '📦 Мульти-конфиги' || echo '🌉 Каскад VPS-to-VPS' )"
    echo -e "  ${BOLD}Публичный IP:${NC}     $PUBLIC_IP"
    echo -e "  ${BOLD}Split Tunnel:${NC}     $( [[ $INSTALL_SPLIT -eq 1 ]] && echo '✅ Да (порт 41820)' || echo '❌ Нет' )"
    echo -e "  ${BOLD}Full Tunnel:${NC}      $( [[ $INSTALL_FULL -eq 1 ]] && echo '✅ Да (порт 41821)' || echo '❌ Нет' )"
    echo -e "  ${BOLD}Smart Update:${NC}     $( [[ $INSTALL_SMART -eq 1 ]] && echo '✅ Да' || echo '❌ Нет' )"
    echo -e "  ${BOLD}AdGuard Home:${NC}     $( [[ $INSTALL_ADGUARD -eq 1 ]] && echo '✅ Да' || echo '❌ Нет' )"
    echo -e "  ${BOLD}Zapret:${NC}           $( [[ $INSTALL_ZAPRET -eq 1 ]] && echo '✅ Да' || echo '❌ Нет' )"
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    read -p "$(echo -e ${YELLOW}Начать установку? [y/n]:${NC} )" -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "Установка отменена"; exit 0; }
}

# ==============================================================================
# ОСНОВНОЙ ПРОЦЕСС УСТАНОВКИ
# ==============================================================================
main() {
    # Проверки
    check_root
    check_os
    
    # Подготовка
    mkdir -p "$TEMP_DIR/modules" "$TEMP_DIR/configs"
    mkdir -p "$AMNEZIA_DIR"/{clients,server-clients,server-clients-full,lists,logs}
    > "$INSTALL_LOG"
    
    print_banner
    
    # Интерактивный выбор
    select_mode
    get_public_ip
    select_local_servers
    select_optional
    select_urls_interactive
    setup_cascade_config
    show_summary
    
    # ============================================================================
    # СКАЧИВАНИЕ И ВЫПОЛНЕНИЕ МОДУЛЕЙ
    # ============================================================================
    echo -e "\n${BOLD}${CYAN}📥 Скачивание модулей из GitHub...${NC}"
    
    # Обязательные модули
    MANDATORY_MODULES=(
        "00-base-system.sh"
        "01-amneziawg.sh"
        "07-routes-updater.sh"
    )
    
    # Модули серверов (в зависимости от выбора)
    [[ $INSTALL_SPLIT -eq 1 ]] && MANDATORY_MODULES+=("02-server-split.sh")
    [[ $INSTALL_FULL -eq 1 ]] && MANDATORY_MODULES+=("03-server-full.sh")
    
    # Режим-зависимые модули
    if [[ "$MODE_NAME" == "multi" ]]; then
        MANDATORY_MODULES+=("04-client-multi.sh")
    else
        MANDATORY_MODULES+=("05-client-cascade.sh")
    fi
    
    # Опциональные модули
    [[ $INSTALL_SMART -eq 1 ]] && MANDATORY_MODULES+=("06-lists-manager.sh")
    [[ $INSTALL_ADGUARD -eq 1 ]] && MANDATORY_MODULES+=("08-adguard.sh")
    [[ $INSTALL_ZAPRET -eq 1 ]] && MANDATORY_MODULES+=("09-zapret.sh")
    
    # Всегда устанавливаем алиасы
    MANDATORY_MODULES+=("10-aliases.sh")
    
    # Скачиваем все модули
    for module in "${MANDATORY_MODULES[@]}"; do
        download_module "$module" || {
            log_error "Критическая ошибка: не удалось скачать $module"
            exit 1
        }
    done
    
    # ============================================================================
    # ВЫПОЛНЕНИЕ МОДУЛЕЙ ПО ОЧЕРЕДИ
    # ============================================================================
    echo -e "\n${BOLD}${CYAN}⚙️  Выполнение модулей...${NC}\n"
    
    # Экспортируем переменные для модулей
    export PUBLIC_IP MODE_NAME AMNEZIA_DIR CURRENT_USER INSTALL_LOG
    
    # 00 - Базовая подготовка
    log_info "🔧 Модуль 00: Базовая подготовка системы"
    bash "$TEMP_DIR/modules/00-base-system.sh" 2>&1 | tee -a "$INSTALL_LOG"
    
    # 01 - AmneziaWG
    log_info "🔧 Модуль 01: Установка AmneziaWG"
    bash "$TEMP_DIR/modules/01-amneziawg.sh" 2>&1 | tee -a "$INSTALL_LOG"
    
    # 02 - Split сервер
    if [[ $INSTALL_SPLIT -eq 1 ]]; then
        log_info "🔧 Модуль 02: Split Tunneling сервер (41820)"
        bash "$TEMP_DIR/modules/02-server-split.sh" 2>&1 | tee -a "$INSTALL_LOG"
    fi
    
    # 03 - Full сервер
    if [[ $INSTALL_FULL -eq 1 ]]; then
        log_info "🔧 Модуль 03: Full Tunnel сервер (41821)"
        bash "$TEMP_DIR/modules/03-server-full.sh" 2>&1 | tee -a "$INSTALL_LOG"
    fi
    
    # 04/05 - Клиент (в зависимости от режима)
    if [[ "$MODE_NAME" == "multi" ]]; then
        log_info "🔧 Модуль 04: Клиент с автопереключением (Multi)"
        bash "$TEMP_DIR/modules/04-client-multi.sh" 2>&1 | tee -a "$INSTALL_LOG"
    else
        log_info "🔧 Модуль 05: Клиент для каскада"
        bash "$TEMP_DIR/modules/05-client-cascade.sh" 2>&1 | tee -a "$INSTALL_LOG"
    fi
    
    # 06 - Smart Update (опционально)
    if [[ $INSTALL_SMART -eq 1 ]]; then
        log_info "🔧 Модуль 06: Smart Update v2.0"
        bash "$TEMP_DIR/modules/06-lists-manager.sh" 2>&1 | tee -a "$INSTALL_LOG"
    fi
    
    # 07 - Обновление маршрутов
    log_info "🔧 Модуль 07: Обновление маршрутов"
    bash "$TEMP_DIR/modules/07-routes-updater.sh" 2>&1 | tee -a "$INSTALL_LOG"
    
    # 08 - AdGuard (опционально)
    if [[ $INSTALL_ADGUARD -eq 1 ]]; then
        log_info "🔧 Модуль 08: AdGuard Home"
        bash "$TEMP_DIR/modules/08-adguard.sh" 2>&1 | tee -a "$INSTALL_LOG"
    fi
    
    # 09 - Zapret (опционально)
    if [[ $INSTALL_ZAPRET -eq 1 ]]; then
        log_info "🔧 Модуль 09: Zapret 2"
        bash "$TEMP_DIR/modules/09-zapret.sh" 2>&1 | tee -a "$INSTALL_LOG"
    fi
    
    # 10 - Алиасы
    log_info "🔧 Модуль 10: Алиасы и команды"
    bash "$TEMP_DIR/modules/10-aliases.sh" 2>&1 | tee -a "$INSTALL_LOG"
    
    # ============================================================================
    # ФИНАЛЬНАЯ НАСТРОЙКА
    # ============================================================================
    log_info "🔧 Финальная настройка..."
    
    # Загружаем базовые списки, если Smart Update установлен
    if [[ $INSTALL_SMART -eq 1 ]]; then
        log_info "🔄 Запуск первичного обновления списков..."
        bash "$AMNEZIA_DIR/update-lists.sh" 2>&1 | tee -a "$INSTALL_LOG" || true
    fi
    
    # Применяем правила маршрутизации
    log_info "🛣️  Применение правил маршрутизации..."
    bash "$AMNEZIA_DIR/update-vpn-routes.sh" 2>&1 | tee -a "$INSTALL_LOG" || true
    
    # Очистка
    rm -rf "$TEMP_DIR"
    
    # ============================================================================
    # ФИНАЛЬНОЕ СООБЩЕНИЕ
    # ============================================================================
    echo -e "\n${BOLD}${GREEN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    🎉 УСТАНОВКА ЗАВЕРШЕНА!                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${BOLD}${CYAN}📋 Следующие шаги:${NC}"
    echo ""
    
    if [[ "$MODE_NAME" == "multi" ]]; then
        echo -e "  ${YELLOW}1.${NC} Загрузите конфиги провайдеров в:"
        echo -e "     ${CYAN}$AMNEZIA_DIR/clients/${NC}"
        echo ""
        echo -e "  ${YELLOW}2.${NC} ⚠️  В каждом .conf файле:"
        echo -e "     • ${RED}Удалите${NC} строку ${CYAN}DNS = ...${NC}"
        echo -e "     • ${GREEN}Добавьте${NC} строку ${CYAN}Table = off${NC} в секцию [Interface]"
        echo ""
        echo -e "  ${YELLOW}3.${NC} Запустите мастер-скрипт:"
        echo -e "     ${GREEN}vpn-reload${NC}"
    else
        echo -e "  ${YELLOW}1.${NC} Создайте конфиг каскада:"
        echo -e "     ${CYAN}nano /etc/amnezia/amneziawg/amnezia-client.conf${NC}"
        echo ""
        echo -e "  ${YELLOW}2.${NC} Запустите клиент:"
        echo -e "     ${GREEN}systemctl start awg-quick@amnezia-client${NC}"
        echo ""
        echo -e "  ${YELLOW}3.${NC} Примените правила:"
        echo -e "     ${GREEN}vpn-update${NC}"
    fi
    
    echo ""
    echo -e "  ${YELLOW}4.${NC} Подключите устройства к VPN:"
    if [[ $INSTALL_SPLIT -eq 1 ]]; then
        echo -e "     • Split Tunneling (порт 41820): ${CYAN}$AMNEZIA_DIR/server-clients/client_01.conf${NC}"
    fi
    if [[ $INSTALL_FULL -eq 1 ]]; then
        echo -e "     • Full Tunnel (порт 41821): ${CYAN}$AMNEZIA_DIR/server-clients-full/client_01.conf${NC}"
    fi
    
    if [[ $INSTALL_ADGUARD -eq 1 ]]; then
        echo ""
        echo -e "  ${YELLOW}5.${NC} 🛡️  AdGuard Home:"
        echo -e "     • Веб-интерфейс: ${CYAN}http://$PUBLIC_IP:3000${NC}"
        echo -e "     • (после настройки закройте порт 3000: ${GREEN}firewall-cmd --remove-port=3000/tcp --permanent && firewall-cmd --reload${NC})"
    fi
    
    echo ""
    echo -e "  ${BOLD}📖 Справка по командам:${NC} ${GREEN}vpn-help${NC}"
    echo -e "  ${BOLD}📝 Лог установки:${NC} ${CYAN}$INSTALL_LOG${NC}"
    echo ""
}

# Запуск
main "$@"