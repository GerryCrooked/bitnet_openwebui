#!/bin/bash

set -e

HUGGINGFACE_TOKEN="ENTER YOUR TOKEN"

echo "🔧 System aktualisieren..."
apt update && apt upgrade -y

echo "📦 Notwendige Pakete installieren..."
apt install -y python3 python3-pip python3-venv git curl jq build-essential autoconf automake libtool cmake python3-dev libssl-dev -y

echo "📁 Projektverzeichnis vorbereiten..."
mkdir -p /root/bitnet/models
cd /root/bitnet

echo "⬇️ BitNet-Repo klonen..."
if [ ! -d ".git" ]; then
  git clone https://github.com/microsoft/BitNet . || echo "✅ Repo bereits vorhanden"
else
  echo "✅ Repo bereits vorhanden"
fi

echo "🐍 Virtuelle Umgebung erstellen..."
python3 -m venv venv
source venv/bin/activate

echo "📦 Python-Abhängigkeiten installieren..."
pip install --upgrade pip
pip install llama-cpp-python --no-binary :all:
pip install fastapi uvicorn httpx watchdog

echo "📥 Lade aktuelles GGUF-Modell von HuggingFace..."
MODEL_REPO="mradermacher/bitnet_b1_58-3B-GGUF"
API_URL="https://huggingface.co/api/models/${MODEL_REPO}/revision/main"

AUTH_HEADER=""
if [ -n "$HUGGINGFACE_TOKEN" ]; then
  AUTH_HEADER="Authorization: Bearer $HUGGINGFACE_TOKEN"
fi

FILENAME=$(curl -s -H "$AUTH_HEADER" "$API_URL" | jq -r '.siblings[] | select(.rfilename | endswith(".gguf")) | .rfilename' | sort | tail -n1)

if [ -z "$FILENAME" ]; then
  echo "❌ Kein GGUF-Modell gefunden. Abbruch."
  exit 1
fi

TARGET_DIR="models/bitnet_b1_58-3B-GGUF"
mkdir -p "$TARGET_DIR"
echo "⬇️ Lade Modell: $FILENAME"
curl -L -H "$AUTH_HEADER" "https://huggingface.co/${MODEL_REPO}/resolve/main/${FILENAME}" -o "${TARGET_DIR}/ggml-model.gguf"

echo "📄 Log vorbereiten..."
touch /var/log/bitnet.log

echo "🧠 Kopiere bitnet_api.py falls nicht vorhanden..."
if [ ! -f /root/bitnet/bitnet_api.py ]; then
  cp /root/bitnet/default_bitnet_api.py /root/bitnet/bitnet_api.py
fi

echo "🔁 Kopiere agents.json falls nicht vorhanden..."
if [ ! -f /root/bitnet/agents.json ]; then
  cp /root/bitnet/default_agents.json /root/bitnet/agents.json
fi

echo "🌐 Kopiere bitnet_proxy.py falls nicht vorhanden..."
if [ ! -f /root/bitnet/bitnet_proxy.py ]; then
  cp /root/bitnet/default_bitnet_proxy.py /root/bitnet/bitnet_proxy.py
fi

echo "🛠️ Systemd-Dienst einrichten (bitnet-api)..."
cat <<EOF > /etc/systemd/system/bitnet-api.service
[Unit]
Description=BitNet API Service
After=network.target

[Service]
ExecStart=/root/bitnet/venv/bin/python /root/bitnet/bitnet_api.py
WorkingDirectory=/root/bitnet
StandardOutput=append:/var/log/bitnet.log
StandardError=append:/var/log/bitnet.log
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "🛠️ Systemd-Dienst einrichten (bitnet-proxy)..."
cat <<EOF > /etc/systemd/system/bitnet-proxy.service
[Unit]
Description=BitNet OpenWebUI Proxy
After=network.target

[Service]
ExecStart=/root/bitnet/venv/bin/uvicorn bitnet_proxy:app --host 0.0.0.0 --port 8001
WorkingDirectory=/root/bitnet
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "🔁 Dienste aktivieren & starten..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable bitnet-api.service
systemctl enable bitnet-proxy.service
systemctl restart bitnet-api.service
systemctl restart bitnet-proxy.service

IP=$(hostname -I | awk '{print $1}')
echo "✅ BitNet API bereit unter http://${IP}:11434"
echo "🌐 Proxy für OpenWebUI unter http://${IP}:8001"
echo "📄 Log: /var/log/bitnet.log"
echo "🧪 Test: curl -X POST http://${IP}:11434/v1/completions -H 'Content-Type: application/json' -d '{"prompt": "Hallo!", "agent": "chat-default"}'"
