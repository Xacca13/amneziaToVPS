# 🚀 AmneziaWG Gateway

Модульная система развертывания отказоустойчивого VPN-шлюза на базе AmneziaWG для CentOS 9 Stream.

## ✨ Возможности

- **Два режима работы:**
  - 📦 **Мульти-конфиги** — автопереключение между провайдерами с тестированием скорости
  - 🌉 **Каскад VPS-to-VPS** — подключение к другому VPS как к шлюзу
- **Split Tunneling** (порт 41820) — через VPN только указанные домены
- **Full Tunnel** (порт 41821) — 100% трафика через VPN
- **Smart Update v2.0** — автозагрузка списков с 3-уровневой фильтрацией
- **massdns** — молниеносный резолвинг сотен тысяч доменов
- **Watchdog** — автовосстановление связи каждую минуту
- **Защита SSH** — ваш IP всегда имеет priority 1

## 🚀 Быстрая установка

```bash
curl -sSL https://raw.githubusercontent.com/Xacca13/amnezia-gateway/main/install.sh | bash
Или клонирование репозитория:
git clone https://github.com/Xacca13/amnezia-gateway.git
cd amnezia-gateway
chmod +x install.sh
./install.sh
```
## 📋 Системные требования

    CentOS 9 Stream (x86_64)
    1 vCPU, 1–2 ГБ RAM
    Права root
    Статический IPv4
## 🎮 Демо процесса установки
```
root@vps:~# ./install.sh 
╔════════════════════════════════════════════════════════════════╗ 
║ 🛡️ AmneziaWG Gateway: Modular Installer (CentOS 9) ║ 
╚════════════════════════════════════════════════════════════════╝ 
📡 ШАГ 1. Выберите режим подключения к интернету (Upstream): 
  1) 📦 Мульти-конфиги (Автопереключение, тест скорости)
  2) 🌉 Каскад VPS-to-VPS (Один статичный VPS)
     Ваш выбор \[1/2\]: 1

  🌐 Укажите публичный IP этого VPS:
      IP: 185.123.45.67
     
📶 ШАГ 2. Какие локальные серверы запустить?
  1) Split (41820) + Full (41821)
  2) Только Split (41820)
  3) Только Full (41821)
     Ваш выбор \[1-3\]: 1
     
🧩 ШАГ 3. Дополнительные опции:
  🧠 Smart Update? y
  🛡️ AdGuard Home? y
  ⚡ Zapret? n

📋 ШАГ 4. Настройка списков маршрутизации:
  Источники для VPN:
    1) ✅ Antifilter + Re-filter
    2) ✅ GubernievS (Roblox/WhatsApp/Google)
    3) ✅ Itdoginfo Services
    4) ✅ Itdoginfo Subnets
    5) 📦 Всё вышеперечисленное
    6) ⚪ Пропустить
     Ваш выбор \[1-6\]: 5
     
  Источники для Direct:
    1) ✅ AntiZapret exclude-hosts
    2) ✅ Itdoginfo outside-kvas
    3) 📦 Оба
    4) ⚪ Пропустить
     Ваш выбор \[1-4\]: 3
     
  Глобальные фильтры (мусор):
    1) ✅ AntiZapret remove-hosts
    2) ✅ OISD Big + NSFW
    3) ✅ AdGuard + HaGeZi
    4) 📦 Все фильтры
    5) ⚪ Пропустить
     Ваш выбор \[1-5\]: 4

════════════════════════════════════════════════════════════════
📋 СВОДКА УСТАНОВКИ
════════════════════════════════════════════════════════════════

Режим:             📦 Мульти-конфиги 
Публичный IP:      185.123.45.67 
Split Tunnel:      ✅ Да (порт 41820) 
Full Tunnel:       ✅ Да (порт 41821) 
Smart Update:      ✅ Да 
AdGuard Home:      ✅ Да 
Zapret:            ❌ Нет 
════════════════════════════════════════════════════════════════

  Начать установку? \[y/n\]: y 
  📥 Скачивание модулей из GitHub... 
  ✓ modules/00-base-system.sh 
  ✓ modules/01-amneziawg.sh 
  ✓ modules/02-server-split.sh 
  ✓ modules/03-server-full.sh 
  ✓ modules/04-client-multi.sh 
  ✓ modules/06-lists-manager.sh 
  ✓ modules/07-routes-updater.sh 
  ✓ modules/08-adguard.sh 
  ✓ modules/10-aliases.sh 
  
  ⚙️ Выполнение модулей... 
  \[00-base\]      ✅ Система обновлена, massdns установлен 
  \[01-amnezia\]   ✅ AmneziaWG установлен, модуль ядра загружен 
  \[02-split\]     ✅ Split Tunneling сервер (порт 41820), 10 клиентов 
  \[03-full\]      ✅ Full Tunnel сервер (порт 41821), 10 клиентов 
  \[04-multi\]     ✅ switch-vpn.sh + Watchdog + timers 
  \[06-lists\]     ✅ Smart Update v2.0, таймер (воскресенье 03:00) 
  \[07-routes\]    ✅ update-vpn-routes.sh создан 
  \[08-adguard\]   ✅ AdGuard Home установлен (порт 53, 3000) 
  \[10-aliases\]   ✅ Алиасы добавлены в .bashrc 
  
  ╔════════════════════════════════════════════════════════════════╗ 
  ║                 🎉 УСТАНОВКА ЗАВЕРШЕНА!                        ║ 
  ╚════════════════════════════════════════════════════════════════╝ 

📋 Следующие шаги:
  1. Загрузите конфиги в ~/amnezia/clients/
  2. Выполните: vpn-reload
  3. Справка:
    vpn-help
    🛡️ AdGuard Home: http://192.168.0.1:3000
root@vps:~#
```
## 🏗️ Архитектура
```
amnezia-gateway/
├── install.sh              # Главный интерактивный установщик
├── modules/                # Модули установки
│   ├── 00-base-system.sh   # Базовая подготовка
│   ├── 01-amneziawg.sh     # AmneziaWG
│   ├── 02-server-split.sh  # Split Tunneling сервер
│   ├── 03-server-full.sh   # Full Tunnel сервер
│   ├── 04-client-multi.sh  # Клиент с автопереключением
│   ├── 05-client-cascade.sh # Клиент для каскада
│   ├── 06-lists-manager.sh # Smart Update
│   ├── 07-routes-updater.sh # Обновление маршрутов
│   ├── 08-adguard.sh       # AdGuard Home
│   ├── 09-zapret.sh        # Zapret 2
│   └── 10-aliases.sh       # Алиасы
├── configs/urls/           # Шаблоны конфигов
```
## 📝 Лицензия
MIT
