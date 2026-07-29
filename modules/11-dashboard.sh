#!/bin/bash
# Модуль 11: Веб-панель управления (Dashboard)
set -e

AMNEZIA_DIR="${AMNEZIA_DIR:-/home/user1/amnezia}"
CURRENT_USER="${CURRENT_USER:-user1}"
INSTALL_LOG="${INSTALL_LOG:-/var/log/amnezia-gateway-install.log}"

log_info() { echo -e "\033[0;36mℹ️  $1\033[0m" | tee -a "$INSTALL_LOG"; }
log_success() { echo -e "\033[0;32m✅ $1\033[0m" | tee -a "$INSTALL_LOG"; }

log_info "📦 Установка зависимостей..."
dnf install -y python3-pip vnstat &>> "$INSTALL_LOG"
systemctl enable --now vnstat &>> "$INSTALL_LOG"

log_info "🐍 Создание venv..."
mkdir -p /opt/vpn-dashboard
cd /opt/vpn-dashboard
python3 -m venv venv &>> "$INSTALL_LOG"
source venv/bin/activate
pip install --upgrade pip &>> "$INSTALL_LOG"
pip install streamlit psutil plotly pandas &>> "$INSTALL_LOG"
deactivate

log_info "📝 Создание app.py..."
cat << 'PYTHON_EOF' > /opt/vpn-dashboard/app.py
import streamlit as st
import subprocess
import os
import psutil
import json
import pandas as pd
import plotly.graph_objects as go

AMNEZIA_DIR = "/home/user1/amnezia"

FILES_TO_EDIT = [
    "include_urls.conf", "include_custom.conf",
    "exclude_urls.conf", "exclude_custom.conf",
    "vpn-domains.conf", "vpn-outside.conf"
]

COMMANDS = {
    "🔄 Полный цикл (списки + маршруты)": "/usr/local/bin/vpn-reload",
    "📥 Только обновить списки": f"{AMNEZIA_DIR}/update-lists.sh",
    "🌐 Только применить маршруты": f"{AMNEZIA_DIR}/apply-routes.sh",
    "🔄 Перезапустить dnsmasq": "systemctl restart dnsmasq",
    "🔄 Синхронизация с Zapret": f"{AMNEZIA_DIR}/sync-vpn-domains-to-zapret.sh",
    "🔁 Перезапуск Watchdog": "systemctl restart vpn-watchdog-cascade.timer"
}

def get_css():
    return """
    <style>
    .stApp { background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%); background-attachment: fixed; color: #e8e8e8; font-size: 1.1rem !important; }
    [data-testid="stAppViewContainer"], [data-testid="stAppViewContainer"] > .stMainBlockContainer { background: transparent !important; }
    h1, h2, h3, h4 { color: #ffffff !important; text-shadow: 0 2px 8px rgba(0,0,0,0.8); }
    h1 { background: linear-gradient(90deg, #ff4d6d, #ff8fa3); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; font-weight: 800; }
    h2 { border-bottom: 2px solid rgba(255,77,109,0.5) !important; }
    .st-emotion-cache-1r6sbt, .st-emotion-cache-1y4p8pa, div[data-testid="stVerticalBlock"] > div { background: rgba(10,15,30,0.75) !important; backdrop-filter: blur(12px); border: 1px solid rgba(255,255,255,0.08); border-radius: 12px; box-shadow: 0 8px 32px rgba(0,0,0,0.5); }
    .stTabs [data-baseweb="tab-list"] { gap: 8px; background: rgba(10,15,30,0.6); padding: 8px; border-radius: 12px; }
    .stTabs [data-baseweb="tab"] { background: rgba(255,255,255,0.05) !important; color: #c0c0c0 !important; border-radius: 8px; padding: 10px 20px; }
    .stTabs [aria-selected="true"] { background: linear-gradient(135deg, #ff4d6d, #c9184a) !important; color: #ffffff !important; font-weight: bold; }
    .stButton > button { background: linear-gradient(135deg, rgba(255,77,109,0.2), rgba(201,24,74,0.2)) !important; color: #ffffff !important; border: 1px solid rgba(255,77,109,0.5) !important; border-radius: 8px; padding: 10px 20px; font-weight: 600; }
    .stButton > button:hover { background: linear-gradient(135deg, #ff4d6d, #c9184a) !important; box-shadow: 0 4px 15px rgba(255,77,109,0.5); }
    [data-testid="stMetric"] { background: rgba(10,15,30,0.7) !important; border: 1px solid rgba(255,77,109,0.2); border-radius: 10px; padding: 15px; }
    [data-testid="stMetricLabel"] { color: #ff8fa3 !important; }
    [data-testid="stMetricValue"] { color: #ffffff !important; }
    .stCodeBlock, div.stCodeBlock > div, pre { background: rgba(5,10,20,0.85) !important; color: #e8e8e8 !important; border: 1px solid rgba(255,77,109,0.2); border-radius: 8px; }
    code { background: rgba(255,77,109,0.15) !important; color: #ff8fa3 !important; border-radius: 4px; padding: 2px 6px; }
    textarea, .stTextArea textarea { background: rgba(5,10,20,0.8) !important; color: #e8e8e8 !important; border: 1px solid rgba(255,77,109,0.3) !important; border-radius: 8px; }
    .stSelectbox > div > div { background: rgba(10,15,30,0.8) !important; color: #e8e8e8 !important; border: 1px solid rgba(255,77,109,0.3) !important; }
    .stAlert { background: rgba(10,15,30,0.8) !important; border: 1px solid rgba(255,77,109,0.3); border-radius: 8px; color: #e8e8e8 !important; }
    p, li, span, div { color: #d0d0d0; }
    strong { color: #ffffff; }
    ::-webkit-scrollbar { width: 10px; }
    ::-webkit-scrollbar-track { background: rgba(10,15,30,0.5); }
    ::-webkit-scrollbar-thumb { background: linear-gradient(180deg, #ff4d6d, #c9184a); border-radius: 5px; }
    hr { border-color: rgba(255,77,109,0.3) !important; }
    </style>
    """

st.set_page_config(page_title="AmneziaWG Dashboard", layout="wide", page_icon="🚀")
st.markdown(get_css(), unsafe_allow_html=True)
st.title("🚀 AmneziaWG Gateway Dashboard (Cascade + dnsmasq)")

tab1, tab2, tab3, tab4 = st.tabs(["📊 Мониторинг", "📝 Редактор", "📈 Процессы", "⚙️ Управление"])

with tab1:
    col1, col2 = st.columns(2)
    with col1:
        st.subheader("🖥️ Состояние VPS")
        st.metric("CPU", f"{psutil.cpu_percent(interval=1)}%")
        ram = psutil.virtual_memory()
        st.metric("RAM", f"{ram.percent}%", f"{ram.used//(1024**2)} / {ram.total//(1024**2)} MB")
        st.subheader("📈 Трафик")
        try:
            vnstat_json = subprocess.run(["vnstat", "--json"], capture_output=True, text=True).stdout
            data = json.loads(vnstat_json)
            hourly = []
            for iface_data in data.get("interfaces", []):
                name = iface_data.get("name", "?")
                for e in iface_data.get("traffic", {}).get("fiveminute", []):
                    if e.get("rx") is not None:
                        t = f"{e['date']['year']}-{e['date']['month']:02d}-{e['date']['day']:02d} {e['time']['hour']:02d}:{e['time']['minute']:02d}"
                        hourly.append({"time": t, "rx": e["rx"]/(1024**2), "tx": e["tx"]/(1024**2), "iface": name})
            if hourly:
                df = pd.DataFrame(hourly)
                fig = go.Figure()
                for iface in df["iface"].unique():
                    d = df[df["iface"] == iface]
                    fig.add_trace(go.Scatter(x=d["time"], y=d["rx"], name=f"{iface} ↓", mode="lines+markers", line=dict(width=3)))
                    fig.add_trace(go.Scatter(x=d["time"], y=d["tx"], name=f"{iface} ↑", mode="lines+markers", line=dict(width=3, dash="dash")))
                fig.update_layout(plot_bgcolor="rgba(10,15,30,0.7)", paper_bgcolor="rgba(10,15,30,0.7)", font=dict(color="#e8e8e8", size=12), hovermode="x unified", xaxis=dict(tickangle=-45))
                st.plotly_chart(fig, use_container_width=True)
            else:
                st.info("ℹ️ Нет данных. Подождите 5-10 мин.")
        except Exception as e:
            st.error(f"⚠️ {e}")
    with col2:
        st.subheader("🔗 AmneziaWG")
        for label, iface in [("Split (awg-server)", "awg-server"), ("Full (awg-server2)", "awg-server2"), ("Cascade (amnezia-client)", "amnezia-client")]:
            st.markdown(f"**{label}:**")
            out = subprocess.run(["awg", "show", iface], capture_output=True, text=True).stdout
            st.code(out if out else "Не активен")

with tab2:
    st.subheader("📝 Редактирование конфигов")
    st.info("💡 Фильтрация рекламы/казино — через AdGuard Home. Здесь только маршрутизация.")
    sel = st.selectbox("Файл:", FILES_TO_EDIT)
    if sel:
        fp = os.path.join(AMNEZIA_DIR, sel)
        content = open(fp, "r", encoding="utf-8").read() if os.path.exists(fp) else f"# {sel}\n"
        new = st.text_area(f"`{sel}`", value=content, height=500)
        if st.button("💾 Сохранить", type="primary"):
            try:
                os.makedirs(AMNEZIA_DIR, exist_ok=True)
                with open(fp, "w", encoding="utf-8") as f:
                    f.write(new)
                st.success(f"✅ `{sel}` сохранён!")
                st.info("ℹ️ Запустите '🔄 Полный цикл' на вкладке Управление.")
            except Exception as e:
                st.error(f"❌ {e}")

with tab3:
    st.subheader("📊 Процессы")
    if st.button("🔄 Обновить"):
        procs = []
        for p in psutil.process_iter(['pid', 'name', 'username', 'cpu_percent', 'memory_percent', 'status']):
            try: procs.append(p.info)
            except: pass
        df = pd.DataFrame(procs)
        c1, c2 = st.columns(2)
        with c1:
            st.markdown("**🔥 Топ-15 CPU:**")
            d = df.sort_values('cpu_percent', ascending=False).head(15)[['pid','name','username','cpu_percent','status']].copy()
            d.columns = ['PID','Имя','User','CPU%','Статус']
            st.dataframe(d, use_container_width=True, hide_index=True)
        with c2:
            st.markdown("**💾 Топ-15 RAM:**")
            d = df.sort_values('memory_percent', ascending=False).head(15)[['pid','name','username','memory_percent','status']].copy()
            d.columns = ['PID','Имя','User','RAM%','Статус']
            st.dataframe(d, use_container_width=True, hide_index=True)

with tab4:
    st.subheader("⚙️ Команды")
    for btn, cmd in COMMANDS.items():
        if st.button(btn, key=btn):
            with st.spinner(f"{btn}..."):
                res = subprocess.run(["bash", "-c", f"source /root/.bashrc 2>/dev/null; {cmd}"], capture_output=True, text=True, cwd=AMNEZIA_DIR)
                if res.returncode == 0:
                    st.success("✅ Успешно!")
                else:
                    st.warning("⚠️ Ошибка/предупреждение")
                if res.stdout.strip() or res.stderr.strip():
                    with st.expander("Вывод"):
                        st.code(f"STDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}")
    st.divider()
    st.markdown(f"Путь: `{AMNEZIA_DIR}`")
PYTHON_EOF

sed -i "s|/home/user1/amnezia|$AMNEZIA_DIR|g" /opt/vpn-dashboard/app.py

log_info "⚙️ systemd сервис..."
cat << 'EOF' > /etc/systemd/system/vpn-dashboard.service
[Unit]
Description=AmneziaWG Dashboard (Streamlit)
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

log_info "🛡️ firewalld: порт 8501 только для VPN..."
firewall-cmd --add-rich-rule='rule family="ipv4" source address="10.8.0.0/24" port port="8501" protocol="tcp" accept' --permanent &>> "$INSTALL_LOG"
firewall-cmd --add-rich-rule='rule family="ipv4" source address="10.9.0.0/24" port port="8501" protocol="tcp" accept' --permanent &>> "$INSTALL_LOG"
firewall-cmd --reload &>> "$INSTALL_LOG"

log_success "🖥️ Dashboard установлен: http://10.8.0.1:8501"