# 🚀 AmneziaWG Gateway

Полное руководство со всеми скриптами — готово к копипасту в терминал

- [Введение](#intro)
- [Архитектура](#architecture)
- [Выбор режима](#modes)
- [Подготовка](#prep)
- [AmneziaWG](#install-awg)
- [Серверы](#servers)
- [Клиент](#client)
- [Списки](#lists)
- [Smart Update](#update-lists)
- [vpn-reload](#reload)
- [Маршруты](#routes)
- [AdGuard](#adguard)
- [Zapret](#zapret)
- [Алиасы](#aliases)
- [Проверка](#test)

## 📖 Введение

### Что это такое?

Полное, пошаговое руководство по развертыванию отказоустойчивого VPN-шлюза на базе AmneziaWG для **CentOS 9 Stream**. Все скрипты ниже можно **скопировать и вставить в терминал целиком** — они самодостаточны.

Система поддерживает **два режима работы**:

- **📦 Мульти-конфиги** — VPS получает набор конфигов от разных провайдеров, автоматически тестирует их и переключается на лучший
- **🌉 Каскад VPS-to-VPS** — один VPS подключается к другому как к шлюзу (упрощенный режим)

### 🎯 Возможности

- **Split Tunneling** (порт 41820) — через VPN идут только указанные домены
- **Full Tunnel** (порт 41821) — 100% трафика через VPN
- **Self-Healing** — Watchdog каждую минуту проверяет связь
- **Smart Update v2.0** — автозагрузка списков с 3-уровневой фильтрацией
- **massdns** — молниеносный резолвинг сотен тысяч доменов за секунды
- **Защита SSH** — ваш IP всегда имеет priority 1 в ip rule

### ⚠️ Системные требования

- CentOS 9 Stream (x86_64)
- 1 vCPU, 1–2 ГБ RAM
- Права `root` (или `sudo`)
- Статический IPv4

### 📋 Содержание

- [2. Подготовка системы](#prep)
- [3. Установка AmneziaWG](#install-awg)
- [4. Серверы (Split + Full)](#servers)
- [5. Клиент (зависит от режима)](#client)
    - [5.1 Мульти-конфиги](#client-multi)
    - [5.2 Каскад VPS-to-VPS](#client-cascade)
- [6. Списки маршрутизации](#lists)
- [7. Smart Update v2.0](#update-lists)
- [8. Мастер-скрипт vpn-reload](#reload)
- [9. Скрипт обновления маршрутов](#routes)
- [10. [Опционально] AdGuard Home](#adguard)
- [11. [Опционально] Zapret 2](#zapret)
- [12. Команды и алиасы](#aliases)
- [13. Финальная проверка](#test)

## 🏗️ Архитектура

### Структура файлов на VPS

/home/$USER/amnezia/

 ├──

clients/

# Конфиги провайдеров (режим Мульти-конфиги)

 │ ├──

provider1.conf

 │ ├──

provider2.conf

 │ └── ... ├──

server-clients/

# Клиентские конфиги Split Tunnel (10 шт)

 │ ├──

client_01.conf

 │ └── ... ├──

server-clients-full/

# Клиентские конфиги Full Tunnel (10 шт)

 │ ├──

client_01.conf

 │ └── ... ├──

lists/

# Скачанные списки (кэш)

 ├──

logs/

# Логи watchdog, update-lists

 ├──

switch-vpn.sh

# Скрипт выбора лучшего сервера (Multi)

 ├──

vpn-watchdog.sh

# Watchdog с переключением (Multi)

 ├──

vpn-watchdog-cascade.sh

# Упрощенный watchdog (Cascade)

 ├──

update-lists.sh

# Smart Update v2.0

 ├──

update-vpn-routes.sh

# Главный скрипт маршрутизации

 ├──

vpn-domains.conf

# Домены через VPN

 ├──

vpn-outside.conf

# Домены напрямую

 ├──

include_urls.conf

# Источники для VPN

 ├──

include_custom.conf

# Ручные домены для VPN

 ├──

exclude_urls.conf

# Источники для Direct

 ├──

exclude_custom.conf

# Ручные домены для Direct

 ├──

filter_urls.conf

# Источники мусора

 └──

filter_custom.conf

# Ручной мусор

/etc/amnezia/amneziawg/

 ├──

awg-server.conf

# Split Tunneling сервер

 ├──

awg-server2.conf

# Full Tunnel сервер

 └──

amnezia-client.conf

# Активный клиентский конфиг

/usr/local/bin/

 └──

vpn-reload

# Мастер-скрипт

## 🔄 Выбор режима работы

💡 **Выберите режим ниже** — все последующие разделы адаптируются.

🎯 Текущий режим:

Мульти-Конфиги

#### 📦 Режим 1: Мульти-Конфиги

**Сценарий:** VPS получает набор конфигов от разных провайдеров

- Автоматическое тестирование скорости
- Переключение на лучший сервер
- Watchdog с исключением сбойных конфигов

#### 🌉 Режим 2: Каскад VPS-to-VPS

**Сценарий:** VPS_A подключается к VPS_B как к шлюзу

- Один статичный конфиг
- Упрощенный Watchdog
- VPS_A = умный роутер, VPS_B = чистый выход

## ⚙️ 2. Подготовка системы

### 1Обновление и установка пакетов

```
dnf update -y
dnf install -y epel-release dnf-plugins-core git curl wget bind-utils \
    iputils ipset iptables iproute jq cronie make gcc pkgconfig tcpdump idn2
dnf config-manager --set-enabled crb
```

### 2Исправление медленного DNS (Критически важно!)

```
chattr -i /etc/resolv.conf 2>/dev/null
cat << 'EOF' > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 1.1.1.1
options timeout:1 attempts:1 rotate inet4
EOF
chattr +i /etc/resolv.conf
sed -i 's/^hosts:.*$/hosts:      files dns/' /etc/nsswitch.conf
systemctl restart systemd-resolved 2>/dev/null || true
```

### 3Создание структуры директорий

```
# Определяем текущего пользователя и формируем путь динамически
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

# Создаем структуру папок
mkdir -p "$AMNEZIA_DIR"/{clients,server-clients,server-clients-full,lists,logs}
mkdir -p /etc/amnezia/amneziawg

# Назначаем права текущему пользователю
chown -R $CURRENT_USER:$CURRENT_USER "$AMNEZIA_DIR" 2>/dev/null || true

# Настройка системных параметров
cat << 'EOF' > /etc/sysctl.d/99-ipforward.conf
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=2
net.ipv4.conf.default.rp_filter=2
EOF
sysctl -p /etc/sysctl.d/99-ipforward.conf
```

### 4Установка massdns для сверхбыстрого резолвинга

Этот шаг критически важен. Он позволяет обрабатывать сотни тысяч доменов за секунды, не перегружая CPU.

```
cd /tmp
git clone https://github.com/blechschmidt/massdns.git
cd massdns
make
sudo cp bin/massdns /usr/local/bin/
sudo chmod +x /usr/local/bin/massdns
sudo restorecon -v /usr/local/bin/massdns  # Исправление контекста SELinux
massdns --version
```

## 🔧 3. Установка AmneziaWG

```
dnf copr enable -y amneziavpn/amneziawg
dnf install -y amneziawg-tools amneziawg-dkms dkms kernel-devel kernel-headers
dkms autoinstall
modprobe amneziawg
lsmod | grep amnezia
```

## 🖥️ 4. Серверы Split и Full Tunnel

### ⚠️ ВАЖНО

Замените `ВАШ_ПУБЛИЧНЫЙ_IP_VPS` в обоих скриптах на реальный IP вашего VPS перед запуском!

### 1Сервер 1: Split Tunneling (порт 41820)

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

cat << SCRIPT > /root/generate_awg.sh
#!/bin/bash
CURRENT_USER=\$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/\$CURRENT_USER/amnezia"
SERVER_PORT=41820
SERVER_PUBLIC_IP="ВАШ_ПУБЛИЧНЫЙ_IP_VPS"
SERVER_INTERFACE="awg-server"
CLIENT_DIR="\$AMNEZIA_DIR/server-clients"

SERVER_PRIV=\$(awg genkey)
SERVER_PUB=\$(echo "\$SERVER_PRIV" | awg pubkey)

cat <<EOF > /etc/amnezia/amneziawg/\${SERVER_INTERFACE}.conf
[Interface]
PrivateKey = \$SERVER_PRIV
Address = 10.8.0.1/24
ListenPort = \$SERVER_PORT
Jc = 3; Jmin = 50; Jmax = 1000; S1 = 25; S2 = 50
H1 = 12345678; H2 = 87654321; H3 = 11223344; H4 = 44332211
PostUp = iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -j MASQUERADE
EOF

for i in \$(seq 1 10); do
    CLIENT_NUM=\$(printf "%02d" \$i)
    CLIENT_IP="10.8.0.\$((i + 1))"
    CLIENT_PRIV=\$(awg genkey)
    CLIENT_PUB=\$(echo "\$CLIENT_PRIV" | awg pubkey)

    cat <<EOF >> /etc/amnezia/amneziawg/\${SERVER_INTERFACE}.conf
[Peer]
PublicKey = \$CLIENT_PUB
AllowedIPs = \$CLIENT_IP/32
EOF

    cat <<EOF > "\$CLIENT_DIR/client_\${CLIENT_NUM}.conf"
[Interface]
PrivateKey = \$CLIENT_PRIV
Address = \$CLIENT_IP/24
DNS = 1.1.1.1, 8.8.8.8
Jc = 3; Jmin = 50; Jmax = 1000; S1 = 25; S2 = 50
H1 = 12345678; H2 = 87654321; H3 = 11223344; H4 = 44332211

[Peer]
PublicKey = \$SERVER_PUB
Endpoint = \$SERVER_PUBLIC_IP:\$SERVER_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
done

chmod 600 /etc/amnezia/amneziawg/\${SERVER_INTERFACE}.conf
SCRIPT

chmod +x /root/generate_awg.sh
/root/generate_awg.sh
systemctl enable --now awg-quick@awg-server
firewall-cmd --add-port=41820/udp --permanent && firewall-cmd --reload
```

### 2Сервер 2: Full Tunnel (порт 41821)

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

cat << SCRIPT > /root/generate_awg2.sh
#!/bin/bash
CURRENT_USER=\$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/\$CURRENT_USER/amnezia"
SERVER_PORT=41821
SERVER_PUBLIC_IP="ВАШ_ПУБЛИЧНЫЙ_IP_VPS"
SERVER_INTERFACE="awg-server2"
CLIENT_DIR="\$AMNEZIA_DIR/server-clients-full"

SERVER_PRIV=\$(awg genkey)
SERVER_PUB=\$(echo "\$SERVER_PRIV" | awg pubkey)

cat <<EOF > /etc/amnezia/amneziawg/\${SERVER_INTERFACE}.conf
[Interface]
PrivateKey = \$SERVER_PRIV
Address = 10.9.0.1/24
ListenPort = \$SERVER_PORT
Jc = 3; Jmin = 50; Jmax = 1000; S1 = 25; S2 = 50
H1 = 12345678; H2 = 87654321; H3 = 11223344; H4 = 44332211
PostUp = iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.9.0.0/24 -j MASQUERADE
EOF

for i in \$(seq 1 10); do
    CLIENT_NUM=\$(printf "%02d" \$i)
    CLIENT_IP="10.9.0.\$((i + 1))"
    CLIENT_PRIV=\$(awg genkey)
    CLIENT_PUB=\$(echo "\$CLIENT_PRIV" | awg pubkey)

    cat <<EOF >> /etc/amnezia/amneziawg/\${SERVER_INTERFACE}.conf
[Peer]
PublicKey = \$CLIENT_PUB
AllowedIPs = \$CLIENT_IP/32
EOF

    cat <<EOF > "\$CLIENT_DIR/client_\${CLIENT_NUM}.conf"
[Interface]
PrivateKey = \$CLIENT_PRIV
Address = \$CLIENT_IP/24
DNS = 1.1.1.1, 8.8.8.8
Jc = 3; Jmin = 50; Jmax = 1000; S1 = 25; S2 = 50
H1 = 12345678; H2 = 87654321; H3 = 11223344; H4 = 44332211

[Peer]
PublicKey = \$SERVER_PUB
Endpoint = \$SERVER_PUBLIC_IP:\$SERVER_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
done

chmod 600 /etc/amnezia/amneziawg/\${SERVER_INTERFACE}.conf
SCRIPT

chmod +x /root/generate_awg2.sh
/root/generate_awg2.sh
systemctl enable --now awg-quick@awg-server2
firewall-cmd --add-port=41821/udp --permanent && firewall-cmd --reload
```

## 🔌 5. Настройка клиента (зависит от режима)

📦 Режим: Мульти-Конфиги

### ⚠️ КРИТИЧНО

В файлах `.conf` провайдеров в папке `$AMNEZIA_DIR/clients/`:

- **Удалите** строку `DNS =...`
- **Добавьте** `Table = off` в секцию `[Interface]`

Это необходимо для корректной работы policy routing.

### 1Скрипт автопереключения (switch-vpn.sh)

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

cat << 'SCRIPT' > "$AMNEZIA_DIR/switch-vpn.sh"
#!/bin/bash
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"
CLIENT_DIR="$AMNEZIA_DIR/clients"
ACTIVE_CONF="/etc/amnezia/amneziawg/amnezia-client.conf"
ACTIVE_SERVICE="awg-quick@amnezia-client"
UPDATE_ROUTES="$AMNEZIA_DIR/update-vpn-routes.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

EXCLUDE_CONF=""
if [[ "$1" == "--exclude" ]]; then EXCLUDE_CONF="$2"; fi

BEST_CONF=""; BEST_PING=9999; BEST_SPEED=0; TOTAL=0; VALID=0

echo -e "${CYAN}🔍 Проверка VPN-серверов...${NC}"
[[ -n "$EXCLUDE_CONF" ]] && echo -e "${YELLOW}⚠️ Исключен: $EXCLUDE_CONF${NC}"

for conf in "$CLIENT_DIR"/*.conf; do
    ((TOTAL++))
    conf_name=$(basename "$conf")

    [[ "$conf_name" == "$EXCLUDE_CONF" ]] && {
        echo -e "${YELLOW}⏭️ [$TOTAL] Пропускаем: $conf_name${NC}";
        continue;
    }

    echo -n "🔄 [$TOTAL] Тестируем $conf_name ... "

    cp "$conf" "$ACTIVE_CONF"; chmod 600 "$ACTIVE_CONF"
    systemctl start "$ACTIVE_SERVICE" 2>/dev/null; sleep 5

    handshake=$(awg show amnezia-client 2>/dev/null | grep "latest handshake" | awk '{print $3, $4, $5}')
    if [[ "$handshake" == "(none)" || -z "$handshake" ]]; then
        echo -e "${RED}✗ Нет handshake${NC}"
        systemctl stop "$ACTIVE_SERVICE" 2>/dev/null; sleep 3; continue
    fi

    ping_time=$(ping -I amnezia-client -c 3 -W 2 1.1.1.1 2>/dev/null | awk -F'/' '/rtt/ {print $5}')
    if [[ -z "$ping_time" ]]; then
        echo -e "${RED}✗ Трафик не проходит${NC}"
        systemctl stop "$ACTIVE_SERVICE" 2>/dev/null; sleep 3; continue
    fi

    speed_time=$(curl -s -o /dev/null -w "%{time_total}" --interface amnezia-client \
        --connect-timeout 4 --max-time 6 "https://speed.cloudflare.com/__down?bytes=100000" 2>/dev/null)
    [[ -z "$speed_time" || "$speed_time" == "0.000" ]] && speed_time="5.0"

    speed_mbps=$(awk -v t="$speed_time" 'BEGIN { if(t>0) printf "%.2f", 0.8/t; else print "0.00" }')

    echo -e "${GREEN}✓${NC} Пинг: ${YELLOW}${ping_time} мс${NC}, Скорость: ${CYAN}${speed_mbps} Мбит/с${NC}"
    ((VALID++))

    is_better=$(awk -v p="$ping_time" -v bp="$BEST_PING" -v s="$speed_mbps" -v bs="$BEST_SPEED" 'BEGIN {
        if (s < 1.0) { print 0; exit }
        if (bp == 9999) { print 1; exit }
        if (p + 0 < bp + 0) { print 1; exit }
        if (p + 0 == bp + 0 && s + 0 > bs + 0) { print 1; exit }
        print 0;
    }')

    [[ "$is_better" == "1" ]] && { BEST_PING="$ping_time"; BEST_SPEED="$speed_mbps"; BEST_CONF="$conf"; }

    systemctl stop "$ACTIVE_SERVICE" 2>/dev/null; sleep 3
done

[[ -z "$BEST_CONF" ]] && { echo -e "${RED}❌ Нет рабочих серверов!${NC}"; exit 1; }

best_name=$(basename "$BEST_CONF")
echo -e "\n${GREEN}🏆 Лучший: $best_name${NC} (Пинг: $BEST_PING мс | Скорость: $BEST_SPEED Мбит/с)"

cp "$BEST_CONF" "$ACTIVE_CONF"; chmod 600 "$ACTIVE_CONF"
systemctl start "$ACTIVE_SERVICE" 2>/dev/null
sleep 2

"$UPDATE_ROUTES" --fast > /dev/null 2>&1
echo -e "${GREEN}✅ Переключено на $best_name${NC}"
SCRIPT

chmod +x "$AMNEZIA_DIR/switch-vpn.sh"
```

### 2Автозапуск каждые 12 часов

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

cat << EOF > /etc/systemd/system/amnezia-switcher.service
[Unit]
Description=AmneziaWG Client Auto-Switcher
After=network.target

[Service]
Type=oneshot
ExecStart=$AMNEZIA_DIR/switch-vpn.sh
User=root
EOF

cat << 'EOF' > /etc/systemd/system/amnezia-switcher.timer
[Unit]
Description=Run AmneziaWG Auto-Switcher every 12 hours

[Timer]
OnCalendar=*-*-* 00/12:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload && systemctl enable --now amnezia-switcher.timer
```

### 3Watchdog (Автовосстановление связи)

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

cat << 'SCRIPT' > "$AMNEZIA_DIR/vpn-watchdog.sh"
#!/bin/bash
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"
CLIENT_DIR="$AMNEZIA_DIR/clients"
ACTIVE_CONF="/etc/amnezia/amneziawg/amnezia-client.conf"
SWITCH_SCRIPT="$AMNEZIA_DIR/switch-vpn.sh"
LOG_FILE="$AMNEZIA_DIR/logs/vpn-watchdog.log"

mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"; }

if ! ip link show amnezia-client >/dev/null 2>&1; then
    log "⚠️ Интерфейс не активен. Аварийное переключение..."
    "$SWITCH_SCRIPT"; exit 0
fi

if ping -I amnezia-client -c 3 -W 2 1.1.1.1 >/dev/null 2>&1; then exit 0; fi
sleep 5
if ping -I amnezia-client -c 3 -W 2 1.1.1.1 >/dev/null 2>&1; then exit 0; fi

log "❌ Нестабильность соединения. Инициируем переключение..."

CURRENT_HOST=$(grep -i '^Endpoint' "$ACTIVE_CONF" 2>/dev/null | cut -d'=' -f2 | xargs | cut -d':' -f1)
CURRENT_CONF_NAME=""
for conf in "$CLIENT_DIR"/*.conf; do
    ep=$(grep -i '^Endpoint' "$conf" 2>/dev/null | cut -d'=' -f2 | xargs)
    h=$(echo "$ep" | cut -d':' -f1)
    if [[ "$h" == "$CURRENT_HOST" ]]; then CURRENT_CONF_NAME=$(basename "$conf"); break; fi
done

if [[ -n "$CURRENT_CONF_NAME" ]]; then
    log "🚫 Исключаем сбойный конфиг: $CURRENT_CONF_NAME"
    "$SWITCH_SCRIPT" --exclude "$CURRENT_CONF_NAME"
else
    "$SWITCH_SCRIPT"
fi

log "✅ Переключение завершено."
SCRIPT

chmod +x "$AMNEZIA_DIR/vpn-watchdog.sh"

cat << EOF > /etc/systemd/system/vpn-watchdog.service
[Unit]
Description=AmneziaWG Connection Watchdog
After=network.target awg-quick@amnezia-client.service

[Service]
Type=oneshot
ExecStart=$AMNEZIA_DIR/vpn-watchdog.sh
User=root
EOF

cat << 'EOF' > /etc/systemd/system/vpn-watchdog.timer
[Unit]
Description=Run VPN Watchdog every 60 seconds

[Timer]
OnBootSec=1min
OnUnitActiveSec=60s
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload && systemctl enable --now vpn-watchdog.timer
```

🌉 Режим: Каскад VPS-to-VPS

### 🌉 Архитектура каскада

**VPS_A** (ваш шлюз) → **VPS_B** (чистый выход) → Интернет

- На VPS_B нужен только AmneziaWG сервер (без Split/Full клиентов)
- На VPS_A — полная настройка с Split/Full серверами
- VPS_A подключается к VPS_B через один статичный конфиг

### 1Подготовка конфига каскада

Создайте конфиг `/etc/amnezia/amneziawg/amnezia-client.conf` вручную или вставьте данные ниже:

```
# Замените значения на свои!
cat << 'EOF' > /etc/amnezia/amneziawg/amnezia-client.conf
[Interface]
PrivateKey = <ПРИВАТНЫЙ_КЛЮЧ_VPS_A>
Address = 10.8.0.2/24
# ВАЖНО: Удалите строку DNS и добавьте Table = off
Table = off
Jc = 3; Jmin = 50; Jmax = 1000; S1 = 25; S2 = 50
H1 = 12345678; H2 = 87654321; H3 = 11223344; H4 = 44332211

[Peer]
PublicKey = <ПУБЛИЧНЫЙ_КЛЮЧ_VPS_B>
Endpoint = <IP_VPS_B>:41820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 /etc/amnezia/amneziawg/amnezia-client.conf
```

#### ⚠️ На VPS_B (сервер-выход) обязательно добавьте:

```
# В секцию [Interface] конфига VPS_B добавьте:
PostUp = iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
PostDown = iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

Без этого при каскаде сайты могут не грузиться из-за проблем с MTU.

### 2Упрощенный Watchdog для каскада

В каскаде не нужно тестировать скорость и переключать серверы — просто рестартим туннель при обрыве связи.

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

cat << 'SCRIPT' > "$AMNEZIA_DIR/vpn-watchdog-cascade.sh"
#!/bin/bash
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"
LOG_FILE="$AMNEZIA_DIR/logs/vpn-watchdog-cascade.log"
ACTIVE_SERVICE="awg-quick@amnezia-client"

mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"; }

# Проверяем, поднят ли интерфейс
if ! ip link show amnezia-client >/dev/null 2>&1; then
    log "⚠️ Интерфейс down. Поднимаем..."
    systemctl start "$ACTIVE_SERVICE"
    exit 0
fi

# Первая проверка
if ping -I amnezia-client -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
    exit 0
fi

# Ждем 5 секунд и проверяем снова
sleep 5
if ping -I amnezia-client -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
    exit 0
fi

# Связь потеряна — перезапускаем туннель
log "❌ Связь потеряна. Перезапуск туннеля..."
systemctl restart "$ACTIVE_SERVICE"
log "✅ Туннель перезапущен"
SCRIPT

chmod +x "$AMNEZIA_DIR/vpn-watchdog-cascade.sh"

cat << EOF > /etc/systemd/system/vpn-watchdog-cascade.service
[Unit]
Description=Cascade VPN Watchdog
After=network.target

[Service]
Type=oneshot
ExecStart=$AMNEZIA_DIR/vpn-watchdog-cascade.sh
User=root
EOF

cat << 'EOF' > /etc/systemd/system/vpn-watchdog-cascade.timer
[Unit]
Description=Run Cascade Watchdog every 60s

[Timer]
OnBootSec=1min
OnUnitActiveSec=60s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload && systemctl enable --now vpn-watchdog-cascade.timer
```

## 📋 6. Списки маршрутизации

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

cat << 'EOF' > "$AMNEZIA_DIR/vpn-domains.conf"
# === Домены и IP, которые идут ЧЕРЕЗ VPN ===
youtube.com
telegram.org
instagram.com
supercell.com
haydaygame.com
EOF
chown $CURRENT_USER:$CURRENT_USER "$AMNEZIA_DIR/vpn-domains.conf"

cat << 'EOF' > "$AMNEZIA_DIR/vpn-outside.conf"
# === Домены и IP, которые идут НАПРЯМУЮ (в обход VPN) ===
sberbank.ru
tinkoff.ru
gosuslugi.ru
yandex.ru
vk.com
avito.ru
wildberries.ru
ozon.ru
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
127.0.0.0/8
EOF
chown $CURRENT_USER:$CURRENT_USER "$AMNEZIA_DIR/vpn-outside.conf"
```

## 🧠 7. Smart Update v2.0

### Умная логика (3 уровня)

1. **Включение:** `include_urls/custom` (для VPN) и `exclude_urls/custom` (для Direct)
2. **Глобальная фильтрация:** `filter_urls/custom` удаляет мертвые домены, мусор и синтаксис AdGuard
3. **Оптимизация:** Автоматическое удаление казино/букмекеров, конвертация кириллицы в Punycode (`idn2`) и схлопывание избыточных поддоменов

### 1Скрипт умного обновления (update-lists.sh)

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

cat << 'SCRIPT' > $AMNEZIA_DIR/update-lists.sh
#!/bin/bash
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

# === Конфигурационные файлы ===
INCLUDE_URLS="$AMNEZIA_DIR/include_urls.conf"
INCLUDE_CUSTOM="$AMNEZIA_DIR/include_custom.conf"
EXCLUDE_URLS="$AMNEZIA_DIR/exclude_urls.conf"
EXCLUDE_CUSTOM="$AMNEZIA_DIR/exclude-custom.conf"
FILTER_URLS="$AMNEZIA_DIR/filter_urls.conf"
FILTER_CUSTOM="$AMNEZIA_DIR/filter_custom.conf"
OUTPUT_DIR="$AMNEZIA_DIR/lists"
TEMP_DIR="/tmp/amnezia-lists"
LOG_FILE="$AMNEZIA_DIR/logs/update-lists.log"
VPN_DOMAINS="$AMNEZIA_DIR/vpn-domains.conf"
VPN_DOMAINS_BACKUP="$AMNEZIA_DIR/vpn-domains-old.conf"
DIRECT_DOMAINS="$AMNEZIA_DIR/vpn-outside.conf"
DIRECT_DOMAINS_BACKUP="$AMNEZIA_DIR/vpn-outside-old.conf"
UPDATE_ROUTES="$AMNEZIA_DIR/update-vpn-routes.sh"

# Regex для фильтрации казино/букмекеров
GAMBLING_REGEX='^[0-9]+|porn|[ck]a+[szc3]+[iley1]+n+[0-9o]|[vw][uy]+[l1]+[kc]a+n|[vw]a+[vw]+a+d+a|x-*bet|most-*bet|leon-*bet|rio-*bet|mel-*bet|ramen-*bet|marathon-*bet|max-*bet|bet-*win|gg-*bet|spin-*bet|banzai-*bet|1iks-*bet|x-*slot|sloto-*zal|max-*slot|bk-*leon|gold-*fishka|play-*fortuna|dragon-*money|poker-*dom|1-*win|crypto-*bos|free-*spin|fair-*spin|no-*deposit|igrovye|avtomaty|bookmaker|zerkalo|slottica|sykaaa|admiral-*x|x-*admiral|pinup-*bet|pari-*match|betting|partypoker|jackpot|bonus|azino[0-9-]|888-*starz|zooma[0-9-]|zenit-*bet|eldorado|slots|vodka|newretro|platinum|igrat|flagman|arkada|\.ua$|\.sex\.|^gama|^xn-+|xn-+|^wheel-.+pinco|-{2,}|(film)?.*lord.*(film)?|\.buzz$|\.pics$|\.work$|\.courses$|\.lat$|\.skin$|\.sbs$|\.kinoza\.|\.kinozi\.|\.men$|\.kz$|herrutor|prostitut'

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"; }

mkdir -p "$OUTPUT_DIR" "$TEMP_DIR" "$(dirname "$LOG_FILE")"
log "${GREEN}🚀 Запуск комплексного обновления списков...${NC}"

# ==============================================================================
# ЭТАП 0: Сборка и очистка глобального списка фильтрации
# ==============================================================================
log "📥 Формирование глобального списка фильтрации..."
> "$TEMP_DIR/remove-hosts-raw.txt"

if [[ -f "$FILTER_URLS" ]]; then
    while IFS= read -r url || [[ -n "$url" ]]; do
        [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue
        url=$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        temp_dl="$TEMP_DIR/filter_dl_$(date +%s%N).tmp"
        if curl -s -L --compressed -A "Mozilla/5.0" --connect-timeout 10 --max-time 60 --retry 5 --retry-delay 2 "$url" -o "$temp_dl" 2>/dev/null; then
            if [[ "$url" == *.gz ]] || file "$temp_dl" | grep -qi "gzip"; then
                gzip -dc "$temp_dl" >> "$TEMP_DIR/remove-hosts-raw.txt" 2>/dev/null
            else
                cat "$temp_dl" >> "$TEMP_DIR/remove-hosts-raw.txt"
            fi
            rm -f "$temp_dl"
            log "${GREEN}✓${NC} Загружен фильтр: $url"
        else
            log "${YELLOW}⚠️ Не удалось загрузить фильтр: $url${NC}"
        fi
    done < "$FILTER_URLS"
fi

if [[ -f "$FILTER_CUSTOM" ]]; then
    cat "$FILTER_CUSTOM" >> "$TEMP_DIR/remove-hosts-raw.txt"
    log "${GREEN}✓${NC} Добавлены ручные фильтры из filter_custom.conf"
fi

log "🧹 Очистка списка фильтрации от синтаксиса AdGuard/Regex и формата hosts..."
sed -E \
    -e '/^[!#\[]/d' \
    -e '/^\/.+/d' \
    -e 's/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+//' \
    -e 's/^\|\|//' \
    -e 's/\^[[:space:]]*$//' \
    -e 's/[[:space:]]+$//' \
    -e 's/.*/\L&/' \
    "$TEMP_DIR/remove-hosts-raw.txt" | \
grep -E '^[a-z0-9]' | \
sort -u > "$TEMP_DIR/remove-hosts.txt"

rm -f "$TEMP_DIR/remove-hosts-raw.txt"
REMOVE_COUNT=$(wc -l < "$TEMP_DIR/remove-hosts.txt" | tr -d ' ')
log "${GREEN}✅ Глобальный список фильтрации готов и очищен (${REMOVE_COUNT} записей).${NC}"

# ==============================================================================
# ЭТАП 1: Универсальная функция обработки списка (VPN или Direct)
# ==============================================================================
process_list() {
    local urls_file="$1"
    local custom_file="$2"
    local target_file="$3"
    local backup_file="$4"
    local list_name="$5"

    log "🔄 Начало обработки списка $list_name..."

    local temp_domains="$TEMP_DIR/${list_name}_domains.tmp"
    local temp_ipv4="$TEMP_DIR/${list_name}_ipv4.tmp"
    local temp_ipv6="$TEMP_DIR/${list_name}_ipv6.tmp"

    > "$temp_domains"; > "$temp_ipv4"; > "$temp_ipv6"

    local CLEAN_SED='s/#.*//; s/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d; s/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+//; s/[]_~:\/?#\[@!$&'\''()*+,;=].*//; s/^\*\.//; s/\.$//; s/.*/\L&/'

    if [[ -f "$urls_file" ]]; then
        while IFS= read -r url || [[ -n "$url" ]]; do
            [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue
            url=$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            log "📥 Скачивание ($list_name): $url"
            local temp_dl="$TEMP_DIR/dl_$(date +%s%N).tmp"
            if curl -s -L --fail --compressed -A "Mozilla/5.0" \
               --connect-timeout 10 --max-time 60 --retry 5 --retry-delay 2 \
               "$url" -o "$temp_dl" 2>/dev/null; then
                grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' "$temp_dl" >> "$temp_ipv4" 2>/dev/null
                grep -Eio '([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}(/[0-9]{1,3})?' "$temp_dl" >> "$temp_ipv6" 2>/dev/null
                sed -E "$CLEAN_SED" "$temp_dl" | \
                grep -E '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]{2,}$' | \
                grep -viE "$GAMBLING_REGEX" >> "$temp_domains"
                rm -f "$temp_dl"
                log "${GREEN}✓${NC} Обработано: $url"
            else
                log "${RED}✗${NC} Ошибка скачивания: $url"
            fi
            sleep 2
        done < "$urls_file"
    fi

    if [[ -f "$custom_file" ]]; then
        log "📂 Чтение пользовательского файла ($list_name): $custom_file"
        grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' "$custom_file" >> "$temp_ipv4" 2>/dev/null
        grep -Eio '([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}(/[0-9]{1,3})?' "$custom_file" >> "$temp_ipv6" 2>/dev/null
        sed -E "$CLEAN_SED" "$custom_file" | \
        grep -E '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]{2,}$' | \
        grep -viE "$GAMBLING_REGEX" >> "$temp_domains"
    else
        cat << CUSTOM_TEMPLATE > "$custom_file"
# === Пользовательские домены и IP для $list_name ===
# Пример: example.com или 192.168.1.0/24
CUSTOM_TEMPLATE
        chown "$CURRENT_USER:$CURRENT_USER" "$custom_file" 2>/dev/null || true
    fi

    log "🧹 Оптимизация и дедупликация списков..."
    sort -u "$temp_domains" -o "$temp_domains"

    local temp_domains_puny="$TEMP_DIR/${list_name}_domains_puny.tmp"
    if command -v idn2 &> /dev/null; then
        while IFS= read -r domain; do
            idn2 "$domain" 2>/dev/null || echo "$domain"
        done < "$temp_domains" > "$temp_domains_puny"
        mv "$temp_domains_puny" "$temp_domains"
    else
        log "${YELLOW}⚠️ Утилита 'idn2' не найдена. Кириллические домены не будут преобразованы.${NC}"
    fi

    local temp_domains_filtered="$TEMP_DIR/${list_name}_domains_filtered.tmp"
    comm -13 "$TEMP_DIR/remove-hosts.txt" "$temp_domains" > "$temp_domains_filtered"

    sed -E '/\..*\./ s/^(www[0-9]*|m|mobile|hd|static|[0-9]+)\.//' "$temp_domains_filtered" | \
    rev | sort -t '.' -k1,1 -k2,2 -k3,3 -k4,4 -k5,5 -k6,6 -k7,7 -k8,8 -k9,9 -k10,10 -k11,11 -k12,12 -k13,13 -k14,14 -k15,15 -k16,16 -k17,17 -k18,18 -k19,19 -k20,20 | \
    awk 'BEGIN { last = "" }
    {
        if (last != "" && index($0, last ".") == 1) { next }
        last = $0
        print $0
    }' | rev | sort -u > "${target_file}.domains.tmp"

    sort -u "$temp_ipv4" > "${target_file}.ipv4.tmp"
    sort -u "$temp_ipv6" > "${target_file}.ipv6.tmp"

    rm -f "$temp_domains" "$temp_domains_filtered"

    grep -vE '^[0-9]|^$' "${target_file}.domains.tmp" > "${target_file}.domains.tmp.safe" 2>/dev/null || true
    mv "${target_file}.domains.tmp.safe" "${target_file}.domains.tmp"

    local domains_count=$(wc -l < "${target_file}.domains.tmp" | tr -d ' ')
    local temp_current="$TEMP_DIR/${list_name}_current.tmp"
    if [[ -f "$target_file" ]]; then
        grep -vE '^#|^$' "$target_file" > "$temp_current" 2>/dev/null || true
    else
        > "$temp_current"
    fi

    if diff -q "$temp_current" <(cat "${target_file}.domains.tmp" "${target_file}.ipv4.tmp" "${target_file}.ipv6.tmp" | sort -u) > /dev/null 2>&1; then
        log "${GREEN}✅ Списки $list_name идентичны. Обновление не требуется.${NC}"
        rm -f "${target_file}.domains.tmp" "${target_file}.ipv4.tmp" "${target_file}.ipv6.tmp" "$temp_current"
        return 0
    fi

    local added=$(comm -13 "$temp_current" <(cat "${target_file}.domains.tmp" "${target_file}.ipv4.tmp" "${target_file}.ipv6.tmp" | sort -u) | wc -l | tr -d ' ')
    local removed=$(comm -23 "$temp_current" <(cat "${target_file}.domains.tmp" "${target_file}.ipv4.tmp" "${target_file}.ipv6.tmp" | sort -u) | wc -l | tr -d ' ')
    local total_combined=$(cat "${target_file}.domains.tmp" "${target_file}.ipv4.tmp" "${target_file}.ipv6.tmp" | sort -u | wc -l | tr -d ' ')

    log "${YELLOW}📊 Обнаружены изменения ($list_name): +$added добавлено, -$removed удалено${NC}"
    log "${YELLOW}💾 Создание бэкапа текущего ${target_file} → ${backup_file}${NC}"
    [[ -f "$target_file" ]] && cp "$target_file" "$backup_file"

    echo "# === Автоматически сгенерированный список для $list_name (Optimized) ===" > "$target_file"
    echo "# Обновлено: $(date '+%Y-%m-%d %H:%M:%S')" >> "$target_file"
    echo "" >> "$target_file"
    echo "# --- Домены ---" >> "$target_file"
    cat "${target_file}.domains.tmp" >> "$target_file"
    echo "" >> "$target_file"
    echo "# --- IPv4 ---" >> "$target_file"
    cat "${target_file}.ipv4.tmp" >> "$target_file"
    echo "" >> "$target_file"
    echo "# --- IPv6 ---" >> "$target_file"
    cat "${target_file}.ipv6.tmp" >> "$target_file"

    chown "$CURRENT_USER:$CURRENT_USER" "$target_file" 2>/dev/null || true
    log "${GREEN}✅ ${target_file} обновлен (${total_combined} записей)${NC}"

    rm -f "${target_file}.domains.tmp" "${target_file}.ipv4.tmp" "${target_file}.ipv6.tmp" "$temp_current"
    return 1
}

# ==============================================================================
# ЭТАП 2: Запуск обработки для обоих направлений
# ==============================================================================
vpn_changed=0
direct_changed=0

process_list "$INCLUDE_URLS" "$INCLUDE_CUSTOM" "$VPN_DOMAINS" "$VPN_DOMAINS_BACKUP" "VPN"
vpn_changed=$?

process_list "$EXCLUDE_URLS" "$EXCLUDE_CUSTOM" "$DIRECT_DOMAINS" "$DIRECT_DOMAINS_BACKUP" "DIRECT"
direct_changed=$?

# ==============================================================================
# ЭТАП 3: Применение изменений
# ==============================================================================
if [[ $vpn_changed -eq 1 || $direct_changed -eq 1 ]]; then
    log ""
    log "${CYAN}🛣 Обнаружены изменения в списках. Запуск резолвинга и обновления iptables...${NC}"
    if [[ -x "$UPDATE_ROUTES" ]]; then
        if "$UPDATE_ROUTES" 2>&1 | tee -a "$LOG_FILE"; then
            log "${GREEN}✅ Правила маршрутизации успешно обновлены!${NC}"
        else
            log "${RED}❌ Ошибка при обновлении правил маршрутизации!${NC}"
        fi
    else
        log "${RED}❌ Скрипт $UPDATE_ROUTES не найден или не исполняемый!${NC}"
    fi
else
    log ""
    log "${GREEN}🎉 Изменений не обнаружено. Обновление маршрутов не требуется.${NC}"
fi

rm -rf "$TEMP_DIR"
log "${GREEN}🏁 Полный цикл обновления завершен!${NC}"
SCRIPT

chmod +x $AMNEZIA_DIR/update-lists.sh
```

### 2Файлы конфигурации (3 пары)

💡 Ниже приведены полные списки источников. Вы можете скопировать готовый скрипт, чтобы создать все файлы сразу.

#### 📥 Источники для VPN (Split Tunneling)

| Источник | Описание |
| --- | --- |
| antifilter/domains.lst | Основной список заблокированных в РФ доменов |
| antifilter/ip.lst | Список IP-адресов заблокированных ресурсов |
| GubernievS (Roblox/WhatsApp/Google...) | IP-подсети крупных сервисов |
| itdoginfo (Services/Subnets) | Детальные списки по категориям |

#### 📤 Источники для Direct (Напрямую)

| Источник | Описание |
| --- | --- |
| exclude-hosts.txt (AntiZapret) | Базовый список исключений от AntiZapret |
| itdoginfo/outside-kvas.lst | Список российских ресурсов |

#### 🗑️ Глобальная фильтрация (Мусор)

| Источник | Описание |
| --- | --- |
| remove-hosts.txt.gz (AntiZapret) | Мертвые и неактуальные домены |
| oisd (domainswild2_big/nsfw) | Глобальные списки мусора |
| AdGuard SDNS Filter / StevenBlack | Фильтры фейковых новостей, азартных игр |
| HaGeZi (nsfw/gambling/fake) | Специализированные блокировки |

#### ⚙️ Скрипт для создания всех конфигов сразу

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

# === 1. Для VPN (через туннель) ===
cat << 'EOF' > "$AMNEZIA_DIR/include_urls.conf"
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
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-hosts.txt
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/fastly-ips.txt
https://raw.githubusercontent.com/bol-van/rulist/refs/heads/main/reestr_hostname.txt
https://github.com/1andrevich/Re-filter-lists/releases/latest/download/ipsum.lst
https://github.com/1andrevich/Re-filter-lists/releases/latest/download/domains_all.lst
https://github.com/1andrevich/Re-filter-lists/raw/refs/heads/main/community_ips.lst
https://github.com/1andrevich/Re-filter-lists/raw/refs/heads/main/community.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/inside-kvas.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Categories/hodca.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/cloudflare.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/cloudfront.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/digitalocean.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/google_ai.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/google_meet.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/google_play.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/hdrezka.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/hetzner.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/ovh.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/roblox.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/telegram.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/tiktok.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/twitter.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Services/youtube.lst
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

cat << 'EOF' > "$AMNEZIA_DIR/include_custom.conf"
# === Пользовательские домены и IP для VPN ===
# Добавьте сюда то, чего нет в автоматических списках
# youtube.com
# telegram.org
EOF

# === 2. Для Direct (напрямую) ===
cat << 'EOF' > "$AMNEZIA_DIR/exclude_urls.conf"
https://github.com/GubernievS/AntiZapret-VPN/raw/refs/heads/main/setup/root/antizapret/download/exclude-hosts.txt
https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/outside-kvas.lst
EOF

cat << 'EOF' > "$AMNEZIA_DIR/exclude-custom.conf"
# === Пользовательские домены и IP для Direct ===
# sberbank.ru
# yandex.ru
# 10.0.0.0/8
# 192.168.0.0/16
EOF

# === 3. Глобальная фильтрация (применяется к VPN и Direct) ===
cat << 'EOF' > "$AMNEZIA_DIR/filter_urls.conf"
https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/remove-hosts.txt.gz
https://github.com/sjhgvr/oisd/raw/refs/heads/main/domainswild2_big.txt
https://raw.githubusercontent.com/sjhgvr/oisd/refs/heads/main/domainswild2_big.txt
https://raw.githubusercontent.com/sjhgvr/oisd/refs/heads/main/domainswild2_nsfw.txt
https://github.com/sjhgvr/oisd/raw/refs/heads/main/domainswild2_nsfw.txt
https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-only/hosts
http://sbc.io/hosts/alternates/fakenews-gambling-porn-only/hosts
https://nsfw.oisd.nl
https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/nsfw-onlydomains.txt
https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/gambling-onlydomains.txt
https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/fake-onlydomains.txt
EOF

cat << 'EOF' > "$AMNEZIA_DIR/filter_custom.conf"
# === Ручной список мусора/мертвых доменов ===
# 0001.hdbaza.net
# 00024.ru
EOF

chown $CURRENT_USER:$CURRENT_USER "$AMNEZIA_DIR"/*urls.conf "$AMNEZIA_DIR"/*custom.conf
```

### 3Systemd сервис для автообновления (раз в неделю)

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

cat << EOF > /etc/systemd/system/amnezia-update-lists.service
[Unit]
Description=AmneziaWG Auto Update Lists
After=network.target

[Service]
Type=oneshot
ExecStart=$AMNEZIA_DIR/update-lists.sh
User=root
StandardOutput=journal
StandardError=journal
EOF

cat << 'EOF' > /etc/systemd/system/amnezia-update-lists.timer
[Unit]
Description=Run AmneziaWG Update Lists weekly
Requires=amnezia-update-lists.service

[Timer]
OnCalendar=Sun 03:00:00
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload && systemctl enable --now amnezia-update-lists.timer
```

## 🔄 8. Мастер-скрипт vpn-reload

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

cat << SCRIPT > /usr/local/bin/vpn-reload
#!/bin/bash
CURRENT_USER=\$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/\$CURRENT_USER/amnezia"

echo "🔄 1. Скачиваем домены из списков, сортируем от повторов, обновляем при необходимости..."
\$AMNEZIA_DIR/update-lists.sh

echo -e "\n📡 2. Пингуем конфиги и выбираем лучший..."
\$AMNEZIA_DIR/switch-vpn.sh

echo -e "\n🔁 3. Перезапускаем VPN-клиент..."
systemctl restart awg-quick@amnezia-client

echo -e "\n🌐 4. Быстро применяем правила (без резолвинга)..."
\$AMNEZIA_DIR/update-vpn-routes.sh --fast

echo -e "\n✅ Готово! Проверяем состояние..."
awg show amnezia-client 2>/dev/null | grep -E "endpoint:|latest handshake:|transfer:" || echo "⚠ Туннель не активен!"

echo -e "\n📋 Быстрая статистика:"
echo "   IP напрямую: \$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || echo 'ошибка')"
echo "   IP через VPN: \$(curl -s --interface amnezia-client --connect-timeout 3 ifconfig.me 2>/dev/null || echo 'ошибка или не настроен')"
SCRIPT

chmod +x /usr/local/bin/vpn-reload
```

## 🛣️ 9. Главный скрипт обновления маршрутов (MassDNS)

Использует massdns для молниеносного резолвинга и ipset restore для атомарной загрузки. Hashsize увеличен до 65536 для оптимальной производительности.

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

cat << 'EOF' > "$AMNEZIA_DIR/update-vpn-routes.sh"
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

# Динамические пути (универсально для любого пользователя)
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

# === 0. Регистрация таблиц и настройки ядра ===
grep -q "^100 " /etc/iproute2/rt_tables 2>/dev/null || echo "100 vpn_split" >> /etc/iproute2/rt_tables
grep -q "^200 " /etc/iproute2/rt_tables 2>/dev/null || echo "200 vpn_full" >> /etc/iproute2/rt_tables

sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv4.conf.all.rp_filter=2 >/dev/null
sysctl -w net.ipv4.conf.default.rp_filter=2 >/dev/null
for iface in $(ls /proc/sys/net/ipv4/conf/); do
    sysctl -w "net.ipv4.conf.$iface.rp_filter=2" >/dev/null 2>&1
done

# === 0.5. АБСОЛЮТНАЯ ЗАЩИТА SSH и локальных проверок ===
SSH_IP=$(who am i 2>/dev/null | awk '{print $5}' | sed 's/(//;s/)//' | cut -d':' -f1)
if [[ -n "$SSH_IP" && "$SSH_IP" != "tty" && "$SSH_IP" != ":0" ]]; then
    ip rule del from all to $SSH_IP/32 table main priority 1 2>/dev/null || true
    ip rule add from all to $SSH_IP/32 table main priority 1
    echo -e "🛡️ Ваш SSH IP (${GREEN}$SSH_IP${NC}) защищен (priority 1)"
fi

# === 1. Резолвинг доменов ===
if [[ $FAST_MODE -eq 0 ]]; then
    # hashsize 65536 оптимизирован для 100k+ записей
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
        local VERBOSE_RESOLVE=0

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
            echo "  ⚡ Запуск massdns (молниеносный режим)..."
            local tmp_resolvers=$(mktemp)
            echo "127.0.0.1" > "$tmp_resolvers"
            echo "9.9.9.9" >> "$tmp_resolvers"
            echo "1.1.1.1" >> "$tmp_resolvers"

            local tmp_resolved_raw=$(mktemp)
            massdns -r "$tmp_resolvers" -t A -t AAAA -o S -w "$tmp_resolved_raw" "$tmp_domains_unique" 2>/dev/null

            awk -v v4="add $set_v4" -v v6="add $set_v6" '
            / IN A / {
                ip = $NF
                print v4, ip
            }
            / IN AAAA / {
                ip = $NF
                print v6, ip
            }
            ' "$tmp_resolved_raw" >> "$tmp_resolved"

            if [[ "$VERBOSE_RESOLVE" == "1" ]]; then
                echo "  📊 Результаты резолвинга (первые 20):"
                awk '/ IN A / {print "  ✅ " $1 " → \033[32m" $NF "\033[0m"}' "$tmp_resolved_raw" | head -n 20
                echo "  ... (остальные скрыты для экономии места)"
            fi

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
        echo "💾 Применяем изменения в ipset (массовая загрузка)..."
        ipset restore -exist < "$TMP_IPSET_CMD" 2>/dev/null
    else
        echo "⚠️ Список изменений пуст, массовая загрузка пропущена."
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
    echo -e "${YELLOW}⏭️  Пропускаем резолвинг${NC}"
fi

# === 2. Таблицы маршрутизации ===
ip route flush table $TABLE_VPN 2>/dev/null || true
ip route flush table $TABLE_FULL 2>/dev/null || true
ip route add default dev $VPN_INTERFACE table $TABLE_VPN
ip route add default dev $VPN_INTERFACE table $TABLE_FULL

# === 3. ip rule (Строгая иерархия приоритетов) ===
ip rule del from all to $SSH_IP/32 table main priority 1 2>/dev/null || true
[[ -n "$SSH_IP" ]] && ip rule add from all to $SSH_IP/32 table main priority 1

ip rule del fwmark 0x2000 table 200 2>/dev/null || true
ip rule add fwmark 0x2000 table 200 priority 2

ip rule del fwmark $MARK_VPN table $TABLE_VPN 2>/dev/null || true
ip rule add fwmark $MARK_VPN table $TABLE_VPN priority 3

ip rule del fwmark $MARK_DIRECT table main 2>/dev/null || true
ip rule add fwmark $MARK_DIRECT table main priority 4

# === 4. iptables mangle — маркировка VPN трафика ===
iptables -t mangle -D PREROUTING -m set --match-set $IPSET_VPN dst -j MARK --set-mark $MARK_VPN 2>/dev/null
iptables -t mangle -D OUTPUT -m set --match-set $IPSET_VPN dst -j MARK --set-mark $MARK_VPN 2>/dev/null
iptables -t mangle -A PREROUTING -m set --match-set $IPSET_VPN dst -j MARK --set-mark $MARK_VPN
iptables -t mangle -A OUTPUT -m set --match-set $IPSET_VPN dst -j MARK --set-mark $MARK_VPN

# === 5. iptables mangle — маркировка Direct трафика (С ИСКЛЮЧЕНИЕМ Full Tunnel) ===
iptables -t mangle -D PREROUTING -m set --match-set $IPSET_DIRECT dst ! -s 10.9.0.0/24 -j MARK --set-mark $MARK_DIRECT 2>/dev/null
iptables -t mangle -D OUTPUT -m set --match-set $IPSET_DIRECT dst ! -s 10.9.0.0/24 -j MARK --set-mark $MARK_DIRECT 2>/dev/null
iptables -t mangle -A PREROUTING -m set --match-set $IPSET_DIRECT dst ! -s 10.9.0.0/24 -j MARK --set-mark $MARK_DIRECT
iptables -t mangle -A OUTPUT -m set --match-set $IPSET_DIRECT dst ! -s 10.9.0.0/24 -j MARK --set-mark $MARK_DIRECT

# === 6. iptables mangle — IPv6 ===
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
    echo "🛡️  Восстанавливаем правила для awg-server2..."
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

echo -e "${GREEN}🎉 Правила раздельного туннелирования успешно и безопасно обновлены.${NC}"
EOF

chmod +x "$AMNEZIA_DIR/update-vpn-routes.sh"
```

## 🛡️ 10. [Опционально] AdGuard Home

### Зачем это нужно?

AdGuard Home превращает ваш VPS в мощный DNS-фильтр. Он будет блокировать рекламу, трекеры, телеметрию и фишинг для всех устройств, подключенных к вашему VPN.

### 1Официальная установка

```
# 1. Освобождаем порт 53 (если он занят)
sudo systemctl stop systemd-resolved 2>/dev/null
sudo systemctl disable systemd-resolved 2>/dev/null
sudo rm -f /etc/resolv.conf
echo -e "nameserver 127.0.0.1\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf
sudo chattr +i /etc/resolv.conf

# 2. Официальная автоматическая установка AdGuard Home
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v

# 3. Разрешаем порты в брандмауэре
sudo firewall-cmd --add-port={53/tcp,53/udp,3000/tcp} --permanent
sudo firewall-cmd --reload

# 4. Проверяем статус сервиса
sudo systemctl status AdGuardHome
```

### 2Первичная настройка через веб-интерфейс

Откройте браузер и перейдите по адресу: `http://<ПУБЛИЧНЫЙ_IP_VPS>:3000`

Пройдите мастер настройки:

- Веб-интерфейс: Оставьте `0.0.0.0:3000`
- DNS-сервер: Укажите `0.0.0.0:53` (критически важно!)
- Придумайте логин и пароль администратора

### 3Настройка вышестоящих DNS (Upstream)

Перейдите в Настройки → Настройки DNS. В поле "Вышестоящие DNS-серверы" замените значения на:

```
https://dns11.quad9.net/dns-query
https://dns.cloudflare.com/dns-query
https://freedns.controld.com/p0
193.58.251.251
https://dns.surfsharkdns.com/dns-query
64.6.64.6
```

✅ Обязательно поставьте галочку **"Параллельные запросы"**.

### 4Добавление списков блокировки (Фильтры)

Перейдите в Фильтры → Списки блокировки → Добавить пользовательский список. Добавьте следующие фильтры:

| Название фильтра | URL |
| --- | --- |
| AdGuard DNS filter | https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt |
| AdGuard Russian filter | https://filters.adtidy.org/android/filters/1_optimized.txt |
| OISD Big | https://big.oisd.nl |
| Peter Lowe's Blocklist | https://adguardteam.github.io/HostlistsRegistry/assets/filter_3.txt |
| EasyList | https://easylist.to/easylist/easylist.txt |
| EasyPrivacy | https://easylist.to/easylist/easyprivacy.txt |
| Phishing Army | https://adguardteam.github.io/HostlistsRegistry/assets/filter_18.txt |
| HaGeZi's Xiaomi Tracker | https://adguardteam.github.io/HostlistsRegistry/assets/filter_60.txt |
| HaGeZi's Windows/Office Tracker | https://adguardteam.github.io/HostlistsRegistry/assets/filter_63.txt |
| HaGeZi's Apple Tracker | https://adguardteam.github.io/HostlistsRegistry/assets/filter_67.txt |

### 5Настройка клиентов

#### ⚠️ КРИТИЧЕСКИ ВАЖНО

Клиенты должны использовать IP-адрес VPN-шлюза VPS в качестве своего DNS-сервера.

В файле конфигурации клиента (например, `client_01.conf`) в секции `[Interface]` укажите:

- Для Split Tunneling (порт 41820): `DNS = 10.8.0.1`
- Для Full Tunneling (порт 41821): `DNS = 10.9.0.1`

Отключите "Частный DNS" / "Безопасный DNS" на клиентских устройствах!

### 6Финальная проверка и безопасность

```
# 1. Проверяем, что AdGuard Home слушает порт 53 на всех интерфейсах
sudo ss -tulpn | grep ':53 '
# (Должно быть *:53 или 0.0.0.0:53)

# 2. Тестируем блокировку рекламы с самого VPS
dig @127.0.0.1 doubleclick.net +short
# (Должен вернуть 0.0.0.0)

# 3. Закрываем порт 3000 от внешнего мира (доступ только через VPN)
sudo firewall-cmd --remove-port=3000/tcp --permanent
sudo firewall-cmd --reload
```

## ⚡ 11. [Опционально] Zapret 2

### Зачем это нужно?

Zapret обходит DPI (Deep Packet Inspection) — позволяет скрыть факт использования VPN от провайдера. Особенно полезно в режиме каскада.

```
dnf install -y luajit-devel lua-devel libcap-devel \
    libnetfilter_queue-devel libmnl-devel zlib-devel systemd-devel

cd /opt
git clone https://github.com/bol-van/zapret2.git
cd zapret2
./install_easy.sh

# При установке выберите:
# - Фаервол: nftables
# - Стратегия: desync или fake (по рекомендации скрипта)
```

## ⌨️ 12. Команды и алиасы

```
CURRENT_USER=$(logname 2>/dev/null || whoami)
AMNEZIA_DIR="/home/$CURRENT_USER/amnezia"

cat << 'EOF' >> /root/.bashrc
# ==============================================================================
# === СПРАВКА ПО ВСЕМ КОМАНДАМ ===
# ==============================================================================
vpn-help() {
    local CYAN='\033[0;36m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local BLUE='\033[0;34m'
    local RED='\033[0;31m'
    local NC='\033[0m'
    local BOLD='\033[1m'

    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║          📖 СПРАВКА ПО КОМАНДАМ AmneziaWG VPN                 ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}${GREEN}🚀 ГЛАВНЫЕ КОМАНДЫ (мастер-скрипты)${NC}"
    echo -e "  ${YELLOW}vpn-reload${NC}        Полный цикл: обновление списков → выбор сервера → применение правил"
    echo -e "  ${YELLOW}vpn-update${NC}        Обновить правила маршрутизации (резолвинг + iptables)"
    echo -e "  ${YELLOW}vpn-fast${NC}          Быстрое обновление правил БЕЗ резолвинга доменов"
    echo -e "  ${YELLOW}vpn-switch${NC}        Проверить все VPN-серверы и переключиться на лучший"
    echo ""
    echo -e "${BOLD}${GREEN}📊 СТАТУСЫ СЕРВЕРОВ И КЛИЕНТА${NC}"
    echo -e "  ${YELLOW}aws${NC}               Полный статус обоих серверов (Split + Full Tunnel)"
    echo -e "  ${YELLOW}aws1${NC}              Статус только Сервера 1 (Split Tunneling, порт 41820)"
    echo -e "  ${YELLOW}aws2${NC}              Статус только Сервера 2 (Full Tunnel, порт 41821)"
    echo -e "  ${YELLOW}awc${NC}               Статус клиентского туннеля (amnezia-client)"
    echo -e "  ${YELLOW}awstatus${NC}          Краткая сводка: активные подключения + правила"
    echo ""
    echo -e "${BOLD}${GREEN}📥 УПРАВЛЕНИЕ СПИСКАМИ (Smart Update)${NC}"
    echo -e "  ${YELLOW}vpn-lists-update${NC}  Запустить обновление списков вручную"
    echo -e "  ${YELLOW}vpn-lists-status${NC}  Статус таймера автообновления (раз в неделю)"
    echo -e "  ${YELLOW}vpn-lists-start${NC}   Принудительно запустить сервис обновления"
    echo -e "  ${YELLOW}vpn-lists-logs${NC}    Последние 50 строк лога обновления"
    echo -e "  ${YELLOW}vpn-stats${NC}         Статистика: количество записей во всех конфигах"
    echo ""
    echo -e "${BOLD}${GREEN}🛡  WATCHDOG (автовосстановление связи)${NC}"
    echo -e "  ${YELLOW}watchdog-status${NC}   Статус таймера Watchdog (проверка каждую минуту)"
    echo -e "  ${YELLOW}watchdog-logs${NC}     Последние 30 строк лога Watchdog"
    echo -e "  ${YELLOW}watchdog-test${NC}     Запустить проверку связи вручную"
    echo ""
    echo -e "${BOLD}${GREEN}✏  РЕДАКТИРОВАНИЕ ФАЙЛОВ (nano)${NC}"
    echo -e "  ${CYAN}Основные списки:${NC}"
    echo -e "    ${YELLOW}edit-vpn${NC}              Редактировать vpn-domains.conf (через VPN)"
    echo -e "    ${YELLOW}edit-direct${NC}           Редактировать vpn-outside.conf (напрямую)"
    echo -e "  ${CYAN}Источники для VPN:${NC}"
    echo -e "    ${YELLOW}edit-include-urls${NC}    Ссылки на списки для VPN"
    echo -e "    ${YELLOW}edit-include-custom${NC}  Ручные домены/IP для VPN"
    echo -e "  ${CYAN}Источники для Direct:${NC}"
    echo -e "    ${YELLOW}edit-exclude-urls${NC}     Ссылки на списки для Direct"
    echo -e "    ${YELLOW}edit-exclude-custom${NC}   Ручные домены/IP для Direct"
    echo -e "  ${CYAN}Глобальные фильтры (мёртвые домены):${NC}"
    echo -e "    ${YELLOW}edit-filter-urls${NC}      Ссылки на списки мёртвых доменов"
    echo -e "    ${YELLOW}edit-filter-custom${NC}    Ручной список мёртвых доменов"
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Алиас для быстрого вызова справки
alias help-vpn='vpn-help'

# === Мастер-скрипты ===
alias vpn-reload='/usr/local/bin/vpn-reload'
alias vpn-update='$AMNEZIA_DIR/update-vpn-routes.sh'
alias vpn-fast='$AMNEZIA_DIR/update-vpn-routes.sh --fast'

# === AmneziaWG: Статусы серверов и клиента ===
alias aws='echo -e "\n\033[1;32m=== 🟢 Сервер 1: Split Tunneling (порт 41820) ===\033[0m" && awg show awg-server && echo -e "\n\033[1;34m=== 🔵 Сервер 2: Full Tunnel (порт 41821) ===\033[0m" && awg show awg-server2'
alias aws1='awg show awg-server'
alias aws2='awg show awg-server2'
alias awc='awg show amnezia-client'
alias awstatus='echo -e "\n\033[1;33m=== 📊 КРАТКАЯ СВОДКА ===\033[0m" && echo -e "\n🟢 Сервер 1:" && awg show awg-server | grep -E "listening port:|endpoint:|latest handshake:|transfer:" && echo -e "\n🔵 Сервер 2:" && awg show awg-server2 | grep -E "listening port:|endpoint:|latest handshake:|transfer:"'

# === VPN алиасы ===
alias vpn-switch='$AMNEZIA_DIR/switch-vpn.sh'

# === Управление двойным обновлением списков ===
alias vpn-lists-update='$AMNEZIA_DIR/update-lists.sh'
alias vpn-lists-status='systemctl status amnezia-update-lists.timer --no-pager'
alias vpn-lists-start='systemctl start amnezia-update-lists.service'
alias vpn-lists-logs='tail -n 50 $AMNEZIA_DIR/logs/update-lists.log'
alias vpn-lists-dir='ls -lh $AMNEZIA_DIR/lists/'

# === Статистика по файлам ===
alias vpn-stats='echo "📊 Статистика списков:" && echo "  vpn-domains.conf:    $(wc -l < $AMNEZIA_DIR/vpn-domains.conf) записей" && echo "  vpn-outside.conf:    $(wc -l < $AMNEZIA_DIR/vpn-outside.conf) записей" && echo "  include_urls:        $(grep -cv "^#\|^$" $AMNEZIA_DIR/include_urls.conf) записей"'

# === Watchdog управление ===
alias watchdog-status='systemctl status vpn-watchdog.timer --no-pager'
alias watchdog-logs='tail -n 30 $AMNEZIA_DIR/logs/vpn-watchdog.log'
alias watchdog-test='$AMNEZIA_DIR/vpn-watchdog.sh'

# === Редактирование файлов ===
alias edit-vpn='nano $AMNEZIA_DIR/vpn-domains.conf'
alias edit-direct='nano $AMNEZIA_DIR/vpn-outside.conf'
alias edit-include-urls='nano $AMNEZIA_DIR/include_urls.conf'
alias edit-include-custom='nano $AMNEZIA_DIR/include_custom.conf'
alias edit-exclude-urls='nano $AMNEZIA_DIR/exclude_urls.conf'
alias edit-exclude-custom='nano $AMNEZIA_DIR/exclude-custom.conf'
alias edit-filter-urls='nano $AMNEZIA_DIR/filter_urls.conf'
alias edit-filter-custom='nano $AMNEZIA_DIR/filter_custom.conf'

# === Быстрый просмотр файлов ===
alias cat-vpn='cat $AMNEZIA_DIR/vpn-domains.conf'
alias cat-direct='cat $AMNEZIA_DIR/vpn-outside.conf'
alias cat-include-urls='cat $AMNEZIA_DIR/include_urls.conf'
alias cat-include-custom='cat $AMNEZIA_DIR/include_custom.conf'
alias cat-exclude-urls='cat $AMNEZIA_DIR/exclude_urls.conf'
alias cat-exclude-custom='cat $AMNEZIA_DIR/exclude-custom.conf'
alias cat-filter-urls='cat $AMNEZIA_DIR/filter_urls.conf'
alias cat-filter-custom='cat $AMNEZIA_DIR/filter_custom.conf'
EOF

source /root/.bashrc
```

## ✅ 13. Финальная проверка

```
# 1. Применяем правила (проверка отсутствия ошибок FIB и SSH)
vpn-update

# 2. Проверяем защиту SSH (должен быть priority 1 с вашим IP)
ip rule show | grep "priority 1"

# 3. Проверяем исключение 2-го сервера из Direct (должно быть "! 10.9.0.0/24")
iptables -t mangle -L PREROUTING -v -n | grep vpn_direct

# 4. Проверяем таблицы (не должно быть ошибок)
ip route show table 100
ip route show table 200

# 5. Тест IP
echo "Напрямую: $(curl -s ifconfig.me)"
echo "Через VPN: $(curl -s --interface amnezia-client ifconfig.me)"

# 6. Проверка двойного автообновления списков
vpn-update
CURRENT_USER=$(logname 2>/dev/null || whoami)
ls -lh /home/$CURRENT_USER/amnezia/lists/

# 7. Проверка бэкапов обоих списков
ls -lh /home/$CURRENT_USER/amnezia/vpn-domains-old.conf /home/$CURRENT_USER/amnezia/vpn-outside-old.conf 2>/dev/null
```

### 🎉 Поздравляем!

Ваша система полностью настроена, защищена от потери доступа и оптимизирована для стабильной работы. Благодаря внедрению `massdns` и `idn2`, обработка сотен тысяч доменов теперь занимает минуты вместо часов.