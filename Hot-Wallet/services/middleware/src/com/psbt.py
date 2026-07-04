import logging
import os
import hashlib
import asyncio
import json
from uuid import uuid4
from pathlib import Path

from src.db import insert_psbt, archive_psbt, get_psbt_byID, get_pending_PSBT, psbt_id_exists, get_walletName
from .btc_core import broadcast_to_bitcoind, decode_rawtx, btc_to_sats, address_wallet_match
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

    psbt_id = data.get("psbt_id"); rawtx = (data.get("tx") or "").strip()
    if not psbt_id or not rawtx:
        log.error("broadcast: missing psbt_id/tx")
        return

    row = await asyncio.to_thread(get_psbt_byID, psbt_id)
    if row is None or row.get("state") != "COLD_STARTED":
        log.warning("broadcast: unknown/wrong state", extra={"psbt_id": psbt_id})
        return

    # .txn = fertige finalisierte Rawtx (keine PSBT). Manipulationsschutz:
    # Rawtx dekodieren und gegen den gestageten DB-Eintrag pruefen.
    try:
        decoded = await asyncio.to_thread(decode_rawtx, rawtx)

    except Exception:
        log.exception("broadcast: rawtx nicht dekodierbar")
        await notify("Cold-Broadcast abgelehnt", f"id={psbt_id}: rawtx ungueltig",
                     priority="urgent", tags="rotating_light")
        return

    target = row.get("target_address"); want = row.get("amount_sats") or 0
    cold  = row.get("source_address") or "cold-multi"
    paid = 0
    for o in decoded.get("vout", []):
        spk = o.get("scriptPubKey", {})
        addr = spk.get("address") or (spk.get("addresses") or [None])[0]
        val = btc_to_sats(o["value"])
        if addr == target:
            paid += val
        else:
            # jede andere Ausgabe MUSS Change der Cold-Wallet sein
            if not addr or not await asyncio.to_thread(address_wallet_match, cold, addr):
                log.error("broadcast: fremde Ausgabe", extra={"psbt_id": psbt_id, "addr": addr})
                await notify("Cold-Broadcast abgelehnt", f"id={psbt_id}: fremde Ausgabe {addr}",
                             priority="urgent", tags="rotating_light")
                return

    if paid != want:
        log.error("broadcast: Betrag weicht ab", extra={"psbt_id": psbt_id, "paid": paid, "want": want})
        await notify("Cold-Broadcast abgelehnt", f"id={psbt_id}: Betrag {paid}!={want}",
                     priority="urgent", tags="rotating_light")
        return

    # Bereits finalisiert -> direkt broadcasten (kein finalizepsbt)
    try:
        txid = await asyncio.to_thread(broadcast_to_bitcoind, rawtx)
        if not txid:
            raise RuntimeError("empty txid")
    except Exception as e:
        log.exception("cold broadcast failed")
        BROADCAST_TOTAL.labels(flow="cold", result="broadcast_failed").inc()
        await notify("Cold-Broadcast fehlgeschlagen", f"id={psbt_id}: {e}",
                     priority="urgent", tags="rotating_light")
        return

    # State + Archiv aus dem DB-Row; psbt bleibt leer -> kein PSBT-Parsing
    psbt_db = await create_psbt(
        psbt_id=psbt_id,
        wallet_type=row.get("wallet_type"),
        rail="OPA_cold",
        psbt="",
        network=row.get("network", "regtest"),
        amount_sats=row.get("amount_sats"),
        target_address=row.get("target_address"),
        source_address=row.get("source_address"),
        changepos=row.get("changepos"),
        sha256=row.get("sha256"),
        meta=row.get("meta") or {},
        state="BROADCASTED",
    )
    await asyncio.to_thread(insert_psbt, psbt_db)
    await asyncio.to_thread(
        archive_psbt, {**psbt_db.model_dump(), "final_tx": rawtx, "txid": txid}
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
