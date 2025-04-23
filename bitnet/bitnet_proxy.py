from fastapi import FastAPI, Request
import httpx
import json
import logging

app = FastAPI()
API_URL = "http://127.0.0.1:11434/v1/completions"

logging.basicConfig(
    filename="/var/log/bitnet_proxy.log",
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)

@app.post("/v1/completions")
async def proxy(request: Request):
    data = await request.json()
    data.setdefault("agent", "chat-default")
    logging.info(f"→ /v1/completions | Agent: {data.get('agent')} | Prompt: {data.get('prompt')}")
    async with httpx.AsyncClient() as client:
        response = await client.post(API_URL, json=data)
        return response.json()

@app.post("/v1/chat/completions")
async def openai_compat_proxy(request: Request):
    openai_data = await request.json()

    # Extrahiere letzte User-Nachricht als Prompt
    messages = openai_data.get("messages", [])
    user_messages = [msg["content"] for msg in messages if msg["role"] == "user"]
    prompt = user_messages[-1] if user_messages else ""

    model = openai_data.get("model", "chat-default")

    # Logging
    logging.info(f"→ /v1/chat/completions | Model: {model} | Prompt: {prompt}")

    # Anfrage an BitNet-API weiterleiten
    async with httpx.AsyncClient() as client:
        response = await client.post(API_URL, json={"prompt": prompt, "agent": model})
        result = response.json()

    # Antwort im OpenAI-kompatiblen Format
    return {
        "id": "chatcmpl-proxy",
        "object": "chat.completion",
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": result["choices"][0]["text"]
                },
                "finish_reason": "stop"
            }
        ]
    }
