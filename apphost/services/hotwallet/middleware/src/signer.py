import hmac
import os
import secrets
import asyncio
import hashlib
import json
import httpx
import logging
import time


from .db import insert_psbt
from .models import PSBTModel
from src.com.ntfy import notify

SIGNER_URL = os.getenv("SIGNER_URL")
SIGNER_PORT = os.getenv("SIGNER_PORT")
SIGNER_HMAC_SECRET = os.getenv("SIGNER_HMAC_SECRET")
SERVICE_NAME = os.getenv("SERVICE_NAME", "middleware")
log = logging.getLogger(SERVICE_NAME)

if not SIGNER_URL:
    raise RuntimeError("SIGNER_URL is not set")

if not SIGNER_HMAC_SECRET:
    raise RuntimeError("SIGNER_HMAC_SECRET is not set")

# HMAC-Secret wird direkt als (Hex-)Env-Variable übergeben, nicht als Datei.
try:
    SIGNER_HMAC_KEY = bytes.fromhex(SIGNER_HMAC_SECRET.strip())
except ValueError as e:
    raise RuntimeError("SIGNER_HMAC_SECRET is not a valid hex string") from e

log = logging.getLogger("middleware")


#Hilfsfunktion für API communication zur Signer VM
def utc_now_epoch() -> str:
    return str(int(time.time()))

async def sign_psbt(psbt: PSBTModel) -> PSBTModel:
    #Weiterleitung zu Sign Funktion
    try:
        signed = await sign_psbt_on_signer(
            psbt.psbt_id,
            psbt.psbt,
            psbt.sha256,
        )
    except Exception as e:
        psbt.state = "SIGNING_FAILED"
        await asyncio.to_thread(
            insert_psbt, psbt
        )
        log.info(f"Ein Fehler ist aufgetreten: {e}")

        await notify("Signing failed", f"id={psbt.psbt_id}: {e}", priority="urgent", tags="rotating_light")
        return
    
    #Bei sign ohne direkten error
    if signed is None or signed.get("psbt") is None:
        psbt.state = "SIGNING_FAILED"
        await asyncio.to_thread(
            insert_psbt, psbt
        )
        log.info("Signing failed")
        await notify("Signing failed", f"id={psbt.psbt_id}", priority="urgent", tags="rotating_light")
        raise RuntimeError("Signer did not return a signed PSBT.")
    
    #Nach erfolgreichen Signieren
    psbt.state = "SIGNED"
    await asyncio.to_thread(
        insert_psbt, psbt
    )
    log.info("PSBT signed successfully.")

    return signed.get("psbt")
        
    

#Sprich NixOs Signer per WG und HMAC an
async def sign_psbt_on_signer(
        psbt_id: str,
        psbt: str,
        sha256: str
    ):
    secret = SIGNER_HMAC_KEY

    timestamp = utc_now_epoch()
    nonce = secrets.token_hex(16)

    payload = {
        "psbt_id": psbt_id,
        "psbt": psbt,
        "sha256": sha256,
    }

    body = json.dumps(
        payload,
        separators=(",", ":"),
        sort_keys=True
    ).encode()

    msg = timestamp.encode() + nonce.encode() + body

    signature = hmac.new(
        secret,
        msg,
        hashlib.sha256
    ).hexdigest()

    headers = {
        "Content-Type": "application/json",
        "X-Timestamp": timestamp,
        "X-Nonce": nonce,
        "X-Signature": signature,
    }
    
    url = f"{SIGNER_URL}:{SIGNER_PORT}/sign"

    log.info(
        f"Sende asynchrone Anfrage an: {url}",
        extra={
            "psbt_id": psbt_id,
            "psbt": psbt,
            "sha256": sha256,
        }
    )

 
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            r = await client.post(
                url,
                content=body,
                headers=headers
            )
            
            log.info(f"Status Code vom Signer erhalten: {r.status_code}")
            
            r.raise_for_status() 
            
            return r.json()
 
    except httpx.HTTPStatusError as e:
        log.error(f"Signer lieferte Fehler-Status: {e.response.status_code} - Text: {e.response.text}")
        raise RuntimeError(f"Signer request failed with status {e.response.status_code}: {e.response.text}") from e
        
    except httpx.RequestError as e:
        log.error(f"Netzwerkfehler beim Verbindungsaufbau: {e}")
        raise RuntimeError(f"Signer network request failed: {e}") from e
    
    except httpx.HTTPError as e:
        log.error(f"Signer request failed: {e}")
        raise RuntimeError(f"Signer request failed: {e}") from e
