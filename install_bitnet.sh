#!/bin/bash

set -e

echo "📦 Installiere BitNet Abhängigkeiten..."

# Systempakete
apt update && apt install -y python3 python3-venv python3-pip curl git

# Arbeitsverzeichnis
mkdir -p /root/bitnet/models
cd /root/bitnet

# Virtuelle Umgebung
python3 -m venv venv
source venv/bin/activate

# Python-Pakete
pip install --upgrade pip
pip install -r requirements.txt || pip install fastapi uvicorn httpx llama-cpp-python

# Beispielmodell falls nicht vorhanden
if [ ! "$(ls -A models/*/*.gguf 2>/dev/null)" ]; then
  echo "⚠️  Kein Modell gefunden. Bitte manuell ein .gguf Modell in /root/bitnet/models/<name>/ ablegen."
fi

# Konfigurationsdateien nur kopieren, wenn sie nicht existieren
[ -f agents.json ] || cp default_agents.json agents.json
[ -f bitnet_api.py ] || cp default_bitnet_api.py bitnet_api.py
[ -f bitnet_proxy.py ] || cp default_bitnet_proxy.py bitnet_proxy.py

# Logging-Verzeichnis
touch /var/log/bitnet.log
chmod 666 /var/log/bitnet.log

# Systemd-Service für API
cat <<EOF > /etc/systemd/system/bitnet-api.service
[Unit]
Description=BitNet API (Uvicorn)
After=network.target

[Service]
WorkingDirectory=/root/bitnet
ExecStart=/root/bitnet/venv/bin/uvicorn bitnet_api:app --host 0.0.0.0 --port 11434
Restart=always
User=root
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
EOF

# Systemd-Service für Proxy
cat <<EOF > /etc/systemd/system/bitnet-proxy.service
[Unit]
Description=BitNet OpenWebUI Proxy
After=network.target

[Service]
WorkingDirectory=/root/bitnet
ExecStart=/root/bitnet/venv/bin/uvicorn bitnet_proxy:app --host 0.0.0.0 --port 8001
Restart=always
User=root
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
EOF

# Dienste aktivieren
systemctl daemon-reload
systemctl enable --now bitnet-api.service
systemctl enable --now bitnet-proxy.service

echo "✅ Setup komplett!"
echo "➡️ API läuft auf http://127.0.0.1:11434"
echo "➡️ Proxy für OpenWebUI läuft auf http://<dein-server>:8001"
