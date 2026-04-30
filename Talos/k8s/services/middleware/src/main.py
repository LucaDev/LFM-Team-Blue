import os, base64
from fastapi import FastAPI, HTTPException
import httpx

app = FastAPI()

DATABASE_URL = os.getenv("DATABASE_URL", "")
OPA_URL = os.getenv("OPA_URL", "")
NATS_URL = os.getenv("NATS_URL", "")
BITCOIND_RPC_URL = os.getenv("BITCOIND_RPC_URL", "")
BITCOIND_RPC_USER = os.getenv("BITCOIND_RPC_USER", "")
BITCOIND_RPC_PASS = os.getenv("BITCOIND_RPC_PASS", "")
NOTIFIER_URL = os.getenv("NOTIFIER_URL", "")

@app.get("/healthz")
def healthz():
    return {"ok": True}

@app.get("/api/v1/intents/{intent_id}/psbt")
def get_psbt(intent_id: str, format: str = "base64"):
    if format != "base64":
        raise HTTPException(400, "only base64 supported")

    # TODO: load PSBT bytes from DB/object-store by intent_id
    # Placeholder: empty PSBT is not valid; return stub marker
    dummy = b"psbt-placeholder"
    return {
        "intent_id": intent_id,
        "psbt_base64": base64.b64encode(dummy).decode("ascii"),
        "created_utc": "TODO"
    }

@app.post("/api/v1/hot/tx")
async def request_hot_tx(intent: dict):
    # TODO: publish event to NATS and store intent in DB
    # TODO: call OPA for allow
    return {"state": "ACCEPTED", "intent": intent}

@app.post("/api/v1/broadcast")
async def broadcast(body: dict):
    raw = body.get("signed_rawtx_hex")
    if not raw:
        raise HTTPException(400, "signed_rawtx_hex required")

    # bitcoind JSON-RPC call (node-only)
    payload = {"jsonrpc":"1.0","id":"b","method":"sendrawtransaction","params":[raw]}
    auth = (BITCOIND_RPC_USER, BITCOIND_RPC_PASS)

    async with httpx.AsyncClient(timeout=20.0) as c:
        r = await c.post(BITCOIND_RPC_URL, json=payload, auth=auth)
        r.raise_for_status()
        data = r.json()
        if data.get("error"):
            raise HTTPException(502, str(data["error"]))
        return {"txid": data["result"]}