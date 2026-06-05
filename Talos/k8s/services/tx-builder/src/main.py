import os
import json
import base64
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import asyncio
from fastapi import FastAPI, HTTPException
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response
from nats.aio.client import Client as NATS

from .logging_setup import setup_logging
from .metrics import INTENTS_TOTAL, UTXO_UNSPENT_GAUGE, PSBT_BUILT_TOTAL
from . import db
from .indexer import sync_chain
from .bitcoind import estimate_sat_per_vb
from .coinselect import select_utxos, estimate_vbytes
from .psbt_builder import build_psbt

app = FastAPI()

SERVICE_NAME = os.getenv("SERVICE_NAME", "tx-builder")
NATS_URL = os.getenv("NATS_URL", "nats://nats:4222")

BITCOIN_NETWORK = os.getenv("BITCOIN_NETWORK", "regtest")
WORK_ROOT = os.getenv("WORK_ROOT", "/var/lib/btc-work/psbt-work")

# Fee estimation config
FEE_TARGET_BLOCKS = int(os.getenv("FEE_TARGET_BLOCKS", "6"))
VIN_VB_P2WSH = int(os.getenv("VIN_VB_P2WSH", "104"))
VOUT_VB = int(os.getenv("VOUT_VB", "31"))

SUBJECT_BUILD_INTENT = "intent.psbt.build.requested"

HOT_DEPOSIT_SCRIPT_HEX = os.getenv("HOT_DEPOSIT_SCRIPT_HEX", "").lower()
COLD_CHANGE_SCRIPT_HEX = os.getenv("COLD_CHANGE_SCRIPT_HEX", "").lower()

MAX_FEE_SATS = int(os.getenv("MAX_FEE_SATS", "50000"))
MAX_FEE_RATE_SAT_VB = int(os.getenv("MAX_FEE_RATE_SAT_VB", "50"))

log = logging.getLogger("tx-builder")

nc: Optional[NATS] = None


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def ensure_dir(p: Path):
    p.mkdir(parents=True, exist_ok=True)


def write_work_item(intent_id: str, psbt_bytes: bytes, meta: dict):
    d = Path(WORK_ROOT) / intent_id
    ensure_dir(d)
    (d / "unappr.psbt").write_bytes(psbt_bytes)
    (d / "meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")


@app.get("/healthz")
def healthz():
    return {"ok": True, "service": SERVICE_NAME}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/v1/work/{intent_id}/psbt")
def get_work_psbt(intent_id: str):
    p = Path(WORK_ROOT) / intent_id / "unappr.psbt"
    if not p.exists():
        raise HTTPException(404, "PSBT not found for intent_id")
    data = p.read_bytes()
    return {"intent_id": intent_id, "psbt_base64": base64.b64encode(data).decode("ascii"), "created_utc": utc_now_iso()}


async def periodic_chain_sync():
    while True:
        try:
            await sync_chain(BITCOIN_NETWORK)
            unspent = db.count_unspent("cold")
            UTXO_UNSPENT_GAUGE.labels(label="cold").set(unspent)
        except Exception as e:
            log.error("chain_sync_failed", extra={"service": SERVICE_NAME, "error": str(e)})
        await asyncio.sleep(5)

async def build_psbt_for_intent(intent: dict) -> Optional[bytes]:
    intent_id = intent["intent_id"]
    amount_sats = int(intent.get("amount_sats", 0))
    if amount_sats <= 0:
        return None

    utxos = db.list_unspent("cold", limit=500)

    sat_vb = await estimate_sat_per_vb(FEE_TARGET_BLOCKS)

    chosen, total = select_utxos(utxos, amount_sats)
    if not chosen:
        return None

    n_in = len(chosen)
    vbytes = estimate_vbytes(n_in, 2, VIN_VB_P2WSH, VOUT_VB)

    #Absolute fee
    fee = sat_vb * vbytes
    if fee > MAX_FEE_SATS:
        log.error("fee_too_high", extra={"fee": fee})
        return None

    #fee rate
    fee_rate = fee / vbytes
    if fee_rate > MAX_FEE_RATE_SAT_VB:
        return None

    chosen, total = select_utxos(utxos, amount_sats + fee)
    if not chosen:
        return None

    n_in = len(chosen)
    vbytes = estimate_vbytes(n_in, 2, VIN_VB_P2WSH, VOUT_VB)
    fee = sat_vb * vbytes

    change = total - amount_sats - fee
    if change < 0:
        return None

    outputs = [(HOT_DEPOSIT_SCRIPT_HEX, amount_sats)]

    return build_psbt(chosen, outputs, COLD_CHANGE_SCRIPT_HEX, change_sats=change)


#Called from middleware
async def handle_intent_build(msg):
    global nc
    if not nc or not nc.is_connected:
        log.error("nats_not_initialized")
        return
        
    try:
        intent = json.loads(msg.data.decode("utf-8"))
        intent_id = intent.get("intent_id")
        if not intent_id:
            return

        INTENTS_TOTAL.labels(type="refill", result="received").inc()

        # build psbt
        psbt_bytes = await build_psbt_for_intent(intent)
        if not psbt_bytes:
            PSBT_BUILT_TOTAL.labels(result="failed").inc()
            INTENTS_TOTAL.labels(type="refill", result="no-psbt").inc()

            evt = {
                "intent_id": intent_id,
                "created_utc": utc_now_iso(),
                "error": "psbt_build_failed"
            }

            if nc:
                await nc.publish("intent.psbt.failed", json.dumps(evt).encode())

            return

        meta = {
            "intent": intent,
            "created_utc": utc_now_iso(),
            "network": BITCOIN_NETWORK
        }
        write_work_item(intent_id, psbt_bytes, meta)

        PSBT_BUILT_TOTAL.labels(result="ok").inc()
        INTENTS_TOTAL.labels(type="refill", result="psbt-created").inc()

        evt = {"intent_id": intent_id, "created_utc": utc_now_iso(), "psbt_ready": True}

        if nc:
            await nc.publish(
                "intent.psbt.created",
                json.dumps({
                    "intent_id": intent_id,
                    "psbt_ready": True,
                    "created_utc": utc_now_iso()
                }).encode()
            )

    except Exception as e:
        log.error("intent_handler_failed", extra={"service": SERVICE_NAME, "error": str(e)})


@app.on_event("startup")
async def startup():
    setup_logging(SERVICE_NAME)
    ensure_dir(Path(WORK_ROOT))

    asyncio.create_task(periodic_chain_sync())

    # NATS setup
    global nc
    nc = NATS()
    await nc.connect(servers=[NATS_URL])

    log.info(
        "nats_connected",
        extra={
            "service": SERVICE_NAME,
            "nats_url": NATS_URL
        }
    )

    await nc.subscribe(
        SUBJECT_BUILD_INTENT,
        cb=handle_intent_build
    )

    log.info(
        "nats_subscribed",
        extra={
            "subject": SUBJECT_BUILD_INTENT
        }
    )

    log.info("tx-builder_started")


@app.on_event("shutdown")
async def shutdown():
    global nc
    if nc:
        await nc.drain()
    log.info("tx-shutdown")