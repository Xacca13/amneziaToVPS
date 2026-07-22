#!/bin/bash
# ==============================================================================
# 🖥️ Модуль 12: Установка Веб-панели управления (Dashboard)
# ==============================================================================

set -e

# Используем глобальные переменные из install.sh, если они есть, иначе задаем дефолтные
AMNEZIA_DIR="${AMNEZIA_DIR:-/root/amnezia}"
CURRENT_USER="${CURRENT_USER:-root}"
INSTALL_LOG="${INSTALL_LOG:-/var/log/amnezia-gateway-install.log}"

log_info() { echo -e "\033[0;36mℹ️  $1\033[0m" | tee -a "$INSTALL_LOG"; }
log_success() { echo -e "\033[0;32m✅ $1\033[0m" | tee -a "$INSTALL_LOG"; }
log_error() { echo -e "\033[0;31m❌ $1\033[0m" | tee -a "$INSTALL_LOG"; }

log_info "📦 Установка зависимостей для Dashboard (python3, vnstat)..."
dnf install -y python3-pip vnstat &>> "$INSTALL_LOG"
systemctl enable --now vnstat &>> "$INSTALL_LOG"

log_info "🐍 Создание виртуального окружения Python..."
mkdir -p /opt/vpn-dashboard
cd /opt/vpn-dashboard
python3 -m venv venv &>> "$INSTALL_LOG"
source venv/bin/activate
pip install --upgrade pip &>> "$INSTALL_LOG"
pip install streamlit psutil plotly &>> "$INSTALL_LOG"
deactivate

log_info "📝 Создание файла приложения app.py..."
# Создаем файл с заглушкой /root/amnezia, которую затем заменим на реальный путь
cat << 'PYTHON_EOF' > /opt/vpn-dashboard/app.py
import streamlit as st
import subprocess
import os
import psutil
import json
import pandas as pd
import plotly.graph_objects as go

AMNEZIA_DIR = "/root/amnezia" # Будет заменено установщиком

FILES_TO_EDIT = ["include_urls.conf", "include_custom.conf", "exclude_urls.conf", "exclude_custom.conf", "filter_urls.conf", "filter_custom.conf"]
COMMANDS = {
    "🔄 Полный перезапуск (vpn-reload)": "/usr/local/bin/vpn-reload",
    "⚡ Быстрое обновление (vpn-fast)": f"{AMNEZIA_DIR}/update-vpn-routes.sh --fast",
    "📡 Переключить сервер (vpn-switch)": f"{AMNEZIA_DIR}/switch-vpn.sh",
    "📥 Обновить списки": f"{AMNEZIA_DIR}/update-lists.sh",
    "🔄 Синхронизация с Zapret": f"{AMNEZIA_DIR}/sync-vpn-domains-to-zapret.sh"
}

def get_css():
    return """
    <style>
    .stApp { background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%); background-attachment: fixed; color: #e8e8e8; font-size: 1.1rem !important; }
    [data-testid="stAppViewContainer"], [data-testid="stAppViewContainer"] > .stMainBlockContainer { background: transparent !important; }
    h1, h2, h3, h4 { color: #ffffff !important; text-shadow: 0 2px 8px rgba(0, 0, 0, 0.8); }
    h1 { background: linear-gradient(90deg, #ff4d6d, #ff8fa3); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; font-weight: 800; }
    h2 { border-bottom: 2px solid rgba(255, 77, 109, 0.5) !important; }
    .st-emotion-cache-1r6sbt, .st-emotion-cache-1y4p8pa, div[data-testid="stVerticalBlock"] > div { background: rgba(10, 15, 30, 0.75) !important; backdrop-filter: blur(12px); border: 1px solid rgba(255, 255, 255, 0.08); border-radius: 12px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5); }
    .stTabs [data-baseweb="tab-list"] { gap: 8px; background: rgba(10, 15, 30, 0.6); padding: 8px; border-radius: 12px; }
    .stTabs [data-baseweb="tab"] { background: rgba(255, 255, 255, 0.05) !important; color: #c0c0c0 !important; border-radius: 8px; padding: 10px 20px; }
    .stTabs [aria-selected="true"] { background: linear-gradient(135deg, #ff4d6d, #c9184a) !important; color: #ffffff !important; font-weight: bold; }
    .stButton > button { background: linear-gradient(135deg, rgba(255, 77, 109, 0.2), rgba(201, 24, 74, 0.2)) !important; color: #ffffff !important; border: 1px solid rgba(255, 77, 109, 0.5) !important; border-radius: 8px; padding: 10px 20px; font-weight: 600; }
    .stButton > button:hover { background: linear-gradient(135deg, #ff4d6d, #c9184a) !important; box-shadow: 0 4px 15px rgba(255, 77, 109, 0.5); }
    [data-testid="stMetric"] { background: rgba(10, 15, 30, 0.7) !important; backdrop-filter: blur(10px); border: 1px solid rgba(255, 77, 109, 0.2); border-radius: 10px; padding: 15px; }
    [data-testid="stMetricLabel"] { color: #ff8fa3 !important; }
    [data-testid="stMetricValue"] { color: #ffffff !important; }
    .stCodeBlock, div.stCodeBlock > div, pre { background: rgba(5, 10, 20, 0.85) !important; color: #e8e8e8 !important; border: 1px solid rgba(255, 77, 109, 0.2); border-radius: 8px; }
    code { background: rgba(255, 77, 109, 0.15) !important; color: #ff8fa3 !important; border-radius: 4px; padding: 2px 6px; }
    .plotly-graph-div { background: rgba(10, 15, 30, 0.7) !important; border: 1px solid rgba(255, 77, 109, 0.3); border-radius: 10px; padding: 15px; margin: 15px 0; }
    textarea, .stTextArea textarea { background: rgba(5, 10, 20, 0.8) !important; color: #e8e8e8 !important; border: 1px solid rgba(255, 77, 109, 0.3) !important; border-radius: 8px; }
    .stSelectbox > div > div { background: rgba(10, 15, 30, 0.8) !important; color: #e8e8e8 !important; border: 1px solid rgba(255, 77, 109, 0.3) !important; }
    .stAlert { background: rgba(10, 15, 30, 0.8) !important; border: 1px solid rgba(255, 77, 109, 0.3); border-radius: 8px; color: #e8e8e8 !important; }
    p, li, span, div { color: #d0d0d0; }
    strong { color: #ffffff; }
    ::-webkit-scrollbar { width: 10px; height: 10px; }
    ::-webkit-scrollbar-track { background: rgba(10, 15, 30, 0.5); }
    ::-webkit-scrollbar-thumb { background: linear-gradient(180deg, #ff4d6d, #c9184a); border-radius: 5px; }
    hr { border-color: rgba(255, 77, 109, 0.3) !important; }
    </style>
    """

st.set_page_config(page_title="AmneziaWG Dashboard", layout="wide", page_icon="🚀")
st.markdown(get_css(), unsafe_allow_html=True)
st.title("🚀 AmneziaWG Gateway Dashboard")

tab1, tab2, tab3, tab4 = st.tabs(["📊 Мониторинг", "📝 Редактор конфигов", "📈 Процессы", "⚙️ Управление"])

with tab1:
    col1, col2 = st.columns(2)
    with col1:
        st.subheader("🖥️ Состояние VPS")
        st.metric("Загрузка CPU", f"{psutil.cpu_percent(interval=1)}%")
        ram = psutil.virtual_memory()
        st.metric("Использование RAM", f"{ram.percent}%", f"{ram.used // (1024**2)} MB / {ram.total // (1024**2)} MB")
        
        st.subheader("📈 Сетевой трафик (графики)")
        try:
            vnstat_json = subprocess.run(["vnstat", "--json"], capture_output=True, text=True).stdout
            data = json.loads(vnstat_json)
            hourly_data = []
            for iface_data in data.get("interfaces", []):
                iface_name = iface_data.get("name", "unknown")
                for entry in iface_data.get("traffic", {}).get("fiveminute", []):
                    if entry.get("rx") is not None and entry.get("tx") is not None:
                        time_str = f"{entry['date']['year']}-{entry['date']['month']:02d}-{entry['date']['day']:02d} {entry['time']['hour']:02d}:{entry['time']['minute']:02d}"
                        hourly_data.append({"time": time_str, "rx": entry["rx"] / (1024**2), "tx": entry["tx"] / (1024**2), "iface": iface_name})
            
            if hourly_data:
                df = pd.DataFrame(hourly_data)
                fig = go.Figure()
                for iface in df["iface"].unique():
                    idata = df[df["iface"] == iface]
                    fig.add_trace(go.Scatter(x=idata["time"], y=idata["rx"], name=f"{iface} (вход)", mode="lines+markers", line=dict(width=3)))
                    fig.add_trace(go.Scatter(x=idata["time"], y=idata["tx"], name=f"{iface} (выход)", mode="lines+markers", line=dict(width=3, dash="dash")))
                fig.update_layout(xaxis_title="Время", yaxis_title="Трафик (MB)", plot_bgcolor="rgba(10, 15, 30, 0.7)", paper_bgcolor="rgba(10, 15, 30, 0.7)", font=dict(color="#e8e8e8", size=12), hovermode="x unified", xaxis=dict(tickangle=-45))
                st.plotly_chart(fig, use_container_width=True)
            else:
                st.info("ℹ️ Нет данных для графика. Подождите 5-10 минут.")
        except Exception as e:
            st.error(f"⚠️ Ошибка графика: {e}")

    with col2:
        st.subheader("🔗 Статус пиров AmneziaWG")
        st.markdown("**Split Tunnel (awg-server):**")
        awg1 = subprocess.run(["awg", "show", "awg-server"], capture_output=True, text=True).stdout
        st.code(awg1 if awg1 else "Не активен")
        st.markdown("**Full Tunnel (awg-server2):**")
        awg2 = subprocess.run(["awg", "show", "awg-server2"], capture_output=True, text=True).stdout
        st.code(awg2 if awg2 else "Не активен")

with tab2:
    st.subheader("📝 Редактирование конфигурационных файлов")
    selected_file = st.selectbox("Выберите файл:", FILES_TO_EDIT)
    if selected_file:
        filepath = os.path.join(AMNEZIA_DIR, selected_file)
        content = ""
        if os.path.exists(filepath):
            with open(filepath, "r", encoding="utf-8") as f: content = f.read()
        else:
            content = f"# Файл {selected_file} еще не создан.\n"
            st.warning(f"⚠️ Файл не найден. Будет создан при сохранении.")
        
        new_content = st.text_area(f"Редактирование: `{selected_file}`", value=content, height=500)
        if st.button("💾 Сохранить изменения", type="primary"):
            try:
                os.makedirs(AMNEZIA_DIR, exist_ok=True)
                with open(filepath, "w", encoding="utf-8") as f: f.write(new_content)
                st.success(f"✅ Файл `{selected_file}` сохранен!")
            except Exception as e: st.error(f"❌ Ошибка: {e}")

with tab3:
    st.subheader("📊 Активные процессы")
    if st.button("🔄 Обновить список"):
        procs = []
        for p in psutil.process_iter(['pid', 'name', 'username', 'cpu_percent', 'memory_percent', 'status']):
            try: procs.append(p.info)
            except: pass
        df = pd.DataFrame(procs)
        col_cpu, col_mem = st.columns(2)
        with col_cpu:
            st.markdown("**🔥 Топ-15 по CPU:**")
            d_cpu = df.sort_values(by='cpu_percent', ascending=False).head(15)[['pid', 'name', 'username', 'cpu_percent', 'status']].copy()
            d_cpu.columns = ['PID', 'Имя', 'Пользователь', 'CPU %', 'Статус']
            st.dataframe(d_cpu, use_container_width=True, hide_index=True)
        with col_mem:
            st.markdown("**💾 Топ-15 по RAM:**")
            d_mem = df.sort_values(by='memory_percent', ascending=False).head(15)[['pid', 'name', 'username', 'memory_percent', 'status']].copy()
            d_mem.columns = ['PID', 'Имя', 'Пользователь', 'RAM %', 'Статус']
            st.dataframe(d_mem, use_container_width=True, hide_index=True)

with tab4:
    st.subheader("⚙️ Быстрые команды")
    for btn_name, cmd_path in COMMANDS.items():
        if st.button(btn_name, key=btn_name):
            with st.spinner(f"Выполняется: {btn_name}..."):
                res = subprocess.run(["bash", "-c", f"source /root/.bashrc && {cmd_path}"], capture_output=True, text=True, cwd=AMNEZIA_DIR)
                if res.returncode == 0: st.success("✅ Успешно!")
                else: st.warning("⚠️ Завершено с предупреждением/ошибкой.")
                st.code(f"=== STDOUT ===\n{res.stdout}\n\n=== STDERR ===\n{res.stderr}")
    st.divider()
    st.markdown(f"- Путь к конфигу: `{AMNEZIA_DIR}`")
PYTHON_EOF

# Заменяем заглушку на реальный путь из переменной окружения установщика
sed -i "s|/root/amnezia|$AMNEZIA_DIR|g" /opt/vpn-dashboard/app.py

log_info "⚙️ Настройка systemd сервиса для Dashboard..."
cat << 'EOF' > /etc/systemd/system/vpn-dashboard.service
[Unit]
Description=AmneziaWG VPN Dashboard (Streamlit)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vpn-dashboard
ExecStart=/opt/vpn-dashboard/venv/bin/streamlit run /opt/vpn-dashboard/app.py --server.port=8501 --server.address=0.0.0.0 --server.headless=true
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload &>> "$INSTALL_LOG"
systemctl enable --now vpn-dashboard.service &>> "$INSTALL_LOG"

log_info "🛡️ Настройка firewalld для Dashboard (порт 8501 только для VPN)..."
firewall-cmd --add-rich-rule='rule family="ipv4" source address="10.8.0.0/24" port port="8501" protocol="tcp" accept' --permanent &>> "$INSTALL_LOG"
firewall-cmd --add-rich-rule='rule family="ipv4" source address="10.9.0.0/24" port port="8501" protocol="tcp" accept' --permanent &>> "$INSTALL_LOG"
firewall-cmd --reload &>> "$INSTALL_LOG"

log_success "🖥️ Веб-панель управления успешно установлена и запущена!"