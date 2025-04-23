from fastapi import FastAPI, Request
import httpx
import json

app = FastAPI()

# Ziel-API (BitNet lokal)
BITNET_API_URL = "http://127.0.0.1:11434/v1/completions"

@app.post("/v1/completions")
async def proxy_to_bitnet(request: Request):
    data = await request.json()

    # Fallback-Agent definieren
    if "agent" not in data:
        data["agent"] = "chat-default"

    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(BITNET_API_URL, json=data)
            return response.json()
    except httpx.RequestError as e:
        return {"error": f"Verbindungsfehler zur BitNet-API: {str(e)}"}
