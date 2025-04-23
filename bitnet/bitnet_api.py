from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
import subprocess
import logging
import uvicorn
import glob
import os
import json
from llama_cpp import Llama

# Logging
LOGFILE = "/var/log/bitnet.log"
logging.basicConfig(
    filename=LOGFILE,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

# Modell automatisch erkennen
gguf_files = sorted(glob.glob("models/*/*.gguf"))
if not gguf_files:
    raise FileNotFoundError("❌ Kein Modell gefunden in 'models/*/*.gguf'")
MODEL_PATH = gguf_files[-1]
logging.info(f"🧠 Verwende Modell: {MODEL_PATH}")

# Agenten laden
AGENT_FILE = "agents.json"
def load_agents():
    try:
        with open(AGENT_FILE, "r", encoding="utf-8") as f:
            agents = json.load(f)
            logging.info("🔁 Agentenkonfiguration neu geladen")
            return {a["id"]: a for a in agents}
    except Exception as e:
        logging.error(f"❌ Fehler beim Laden der Agenten: {e}")
        return {}

agents = load_agents()

# Llama-Modell laden
llm = Llama(model_path=MODEL_PATH, n_ctx=4096, n_threads=os.cpu_count() or 4, verbose=False)

# FastAPI App definieren
app = FastAPI()

# CORS (für Frontend wie OpenWebUI)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
def startup():
    logging.info("🚀 BitNet API manuell gestartet")

@app.on_event("shutdown")
def shutdown():
    logging.info("🛑 BitNet API beendet")

@app.post("/v1/completions")
async def complete(request: Request):
    req_data = await request.json()

    prompt = req_data.get("prompt", "")
    agent_id = req_data.get("agent", "chat-default")
    agent = agents.get(agent_id)

    if not agent:
        return {"error": f"Agent '{agent_id}' nicht gefunden"}

    system_prompt = agent["system_prompt"]
    user_prompt = f"\nNachricht: {prompt}\n"

    logging.info(f"🔍 Agent '{agent['name']}' (ID: {agent_id}) → Prompt: {prompt}")

    full_prompt = f"{system_prompt}{user_prompt}"

    try:
        output = llm(full_prompt, stop=["</s>", "Nachricht:"], echo=False, temperature=0.7, max_tokens=512)
        response = output["choices"][0]["text"].strip()

        logging.info(f"💬 Antwort von {agent['name']}: {response[:120]}...")
        return {
            "choices": [{"text": response}],
            "agent": agent_id,
            "agent_name": agent["name"]
        }
    except Exception as e:
        logging.error(f"❌ Fehler bei Verarbeitung: {e}")
        return {"error": str(e)}

# Direkter Start (optional)
if __name__ == "__main__":
    uvicorn.run("bitnet_api:app", host="0.0.0.0", port=11434, reload=False)
