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

## 📖 Документация

    Полное руководство со скриптами
     — все скрипты с комментариями, готовые к копипасту
    Руководство по установщику
     — описание работы install.sh

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
└── docs/                   # Документация
```
## 📝 Лицензия
MIT

## 🤝 Вклад
Pull requests приветствуются!
