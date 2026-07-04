import logging
import os
import hashlib
import asyncio
import json
from uuid import uuid4
from pathlib import Path

from src.db import insert_psbt, archive_psbt, get_psbt_byID, get_pending_PSBT, psbt_id_exists, get_walletName
from .btc_core import broadcast_to_bitcoind, psbt_finalize
from src.models import create_psbt_msg, create_psbt
from src.com.ntfy import notify
from src.metrics import BROADCAST_TOTAL

SERVICE_NAME = os.getenv("SERVICE_NAME", "middleware")
BITCOIN_NETWORK = os.getenv("BITCOIN_NETWORK", "regtest")

REFILL_FILE = Path(os.getenv("REFILL_PSBT", "/run/refill.psbt"))
REFILL_FILE.parent.mkdir(parents=True, exist_ok=True)
REFILL_ID_FILE = REFILL_FILE.with_suffix(REFILL_FILE.suffix + ".id")

log = logging.getLogger(SERVICE_NAME)


def hash_psbt(psbt: str) -> str:
    return hashlib.sha256(psbt.encode()).hexdigest()


#Export-Cleanup
async def cleanup_refill(msg):

    row = await asyncio.to_thread(get_pending_PSBT)          # WAITING_HUMAN (Single-TX)

    if row is None:
        log.warning("export.done: keine WAITING_HUMAN PSBT")
        return
    
    row['rail'] = "OPA_cold"; row['psbt'] = load_psbt() or ""

    psbt = await create_psbt_msg(row)

    psbt.state = "COLD_STARTED"
    await asyncio.to_thread(
        insert_psbt, psbt
    )

    await delete_psbt()                                     # staged file + id sidecar
    log.info("refill exported -> COLD_STARTED", extra={"psbt_id": psbt.psbt_id})


async def refill_broadcast(msg):
    data = json.loads(msg.data.decode())

    psbt_id = data.get("psbt_id"); psbt_signed = (data.get("psbt") or "").strip()
    if not psbt_id or not psbt_signed:
        log.error("broadcast: missing psbt_id/psbt")
        return
    
    row = await asyncio.to_thread(get_psbt_byID, psbt_id)
    if row is None or row.get("state") != "COLD_STARTED":
        log.warning("broadcast: unknown/wrong state", extra={"psbt_id": psbt_id})
        return
    
    row['rail'] = "OPA_cold"; row['psbt'] = psbt_signed
    
    psbt_db = await create_psbt_msg(row)

    signed_parsed = await create_psbt(
        psbt_id=psbt_db.psbt_id,
        wallet_type=psbt_db.wallet_type,
        rail=psbt_db.rail,
        psbt=psbt_signed,
        network=psbt_db.network,
        changepos=psbt_db.changepos,
        source_address=psbt_db.source_address,
        state=psbt_db.state,
        meta=psbt_db.meta,
        error_code=psbt_db.error_code
    )

    if (signed_parsed.amount_sats != psbt_db.amount_sats or signed_parsed.target_address != psbt_db.target_address):
        log.error(
            "broadcast: signed PSBT weicht vom DB-Eintrag ab", 
            extra={"psbt_id": psbt_id}
        )
        await notify(
            "Cold-Broadcast abgelehnt", 
            f"id={psbt_id}: PSBT weicht ab",
            priority="urgent",
            tags="rotating_light"
        )
        return
    
    try:
        rawtx_hex = await asyncio.to_thread(psbt_finalize, psbt_signed)
        txid = await asyncio.to_thread(broadcast_to_bitcoind, rawtx_hex)
        if not txid:
            raise RuntimeError("empty txid")
        
    except Exception as e:
        log.exception("cold broadcast failed")
        BROADCAST_TOTAL.labels(flow="cold", result="broadcast_failed").inc()
        await notify(
            "Cold-Broadcast fehlgeschlagen",
            f"id={psbt_id}: {e}",
            priority="urgent",
            tags="rotating_light"
        )
        return
    
    psbt_db.state = "BROADCASTED"
    await asyncio.to_thread(
        insert_psbt, psbt_db
    )

    await asyncio.to_thread(
        archive_psbt, 
        {**psbt_db.model_dump(),
        "final_tx": rawtx_hex,
        "txid": txid}
    )

    BROADCAST_TOTAL.labels(flow="cold", result="ok").inc()
    log.info("cold broadcast ok", extra={"psbt_id": psbt_id, "txid": txid})

# Manual-Submit (rail=manual) – nur über NATS, nicht mehr per HTTP
async def load_manual(msg):
    data = json.loads(msg.data.decode())
    psbt_b64 = data.get("psbt")

    if not psbt_b64:
        log.error("submit: missing psbt")
        return
    
    psbt_id = data.get("id")
    if not psbt_id:
        while True:
            psbt_id = str(uuid4())
            if not await asyncio.to_thread(psbt_id_exists, psbt_id): 
                break

    source = (await asyncio.to_thread(get_walletName, "hot"))[0]

    return await create_psbt(
        psbt_id=psbt_id,
        rail="manual",
        wallet_type="hot",
        psbt=psbt_b64,
        meta={"rail": "manual"},
        network=BITCOIN_NETWORK,
        source_address=source,
        sha256=data.get("sha256"),
        state="PSBT_CREATED"
    )

async def save_psbt(psbt: str, psbt_id: str | None = None):
    pending = get_pending_PSBT()
    if pending is not None:
        log.info("deleting old refill PSBT", extra={"psbt_id": pending.get("psbt_id")})
        await delete_psbt(pending["psbt_id"])   # COLD_STOPPED + unlink

    REFILL_FILE.write_text(psbt)
    if psbt_id is not None:
        REFILL_ID_FILE.write_text(psbt_id)

def load_psbt():
    if not REFILL_FILE.exists():
        return None
    return REFILL_FILE.read_text()


#Löscht nicht, sondern schriebt COLD_STOPPED
async def delete_psbt(psbt_id = None):
    if psbt_id is not None:
        psbt_info = get_psbt_byID(psbt_id)
        if psbt_info is not None:
            psbt = await create_psbt(
                psbt_id=psbt_info["psbt_id"],
                wallet_type=psbt_info["wallet_type"],
                rail="OPA_cold",
                psbt="",
                network=psbt_info.get("network", "regtest"),
                source_address=psbt_info["source_address"],
                target_address=psbt_info["target_address"],
                amount_sats=psbt_info.get("amount_sats") or 0,
                state="COLD_STOPPED",
                meta=psbt_info.get("meta") or {},
            )
            insert_psbt(psbt)

    if REFILL_FILE.exists():
        REFILL_FILE.unlink()
    if REFILL_ID_FILE.exists():
        REFILL_ID_FILE.unlink()
