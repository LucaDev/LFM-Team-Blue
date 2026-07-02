import logging
import os
import hashlib
import asyncio
import json
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import PlainTextResponse

from src.signer import load_psbt, delete_psbt
from src.db import insert_psbt, archive_psbt, get_psbt_byID, get_pending_PSBT
from .btc_core import broadcast_to_bitcoind, psbt_finalize
from src.models import create_psbt_msg, create_psbt
from .metrics import BROADCAST_TOTAL

SERVICE_NAME = os.getenv("SERVICE_NAME", "middleware")

log = logging.getLogger(SERVICE_NAME)

router = APIRouter(prefix="/api/v1/request", tags=["psbt"])


def hash_psbt(psbt: str) -> str:
    return hashlib.sha256(psbt.encode()).hexdigest()


@router.get("/psbt")
async def psbt():

    psbt_str = load_psbt()
    if psbt_str is None:
        raise HTTPException(status_code=404, detail="No PSBT available")

    psbt_db = get_pending_PSBT()
    if psbt_db is None:
        raise HTTPException(status_code=404, detail="No pending PSBT")

    psbt_id = psbt_db.get("psbt_id")
    if psbt_id is None:
        raise HTTPException(status_code=404, detail="Unknown psbt_id")
    psbt_db['rail'] = "OPA_cold"
    psbt_db['psbt'] = psbt_str
    psbt = await create_psbt_msg(psbt_db)

    if psbt is None:
        raise HTTPException(status_code=404, detail="No refill PSBT available")

    #Nur loeschen der Datei, nicht Status überschreiben
    await delete_psbt()
    

    psbt.state = "COLD_STARTED"
    await asyncio.to_thread(
        insert_psbt, psbt
    )

    payload = json.dumps({
        "psbt_id": psbt_id,
        "psbt": psbt_str
    })

    return PlainTextResponse(payload)


@router.post("/broadcast/{psbt_id}")
async def broadcast_psbt(psbt_id: str, request: Request):

    psbt_signed = (await request.body()).decode().strip()

    if not psbt_signed:
        raise HTTPException(status_code=400, detail="Empty PSBT")
    
    psbt_db = get_psbt_byID(psbt_id)
    if psbt_db is None:
        log.warning(f"PSBT not found for broadcast psbt_id={psbt_id}")
        raise HTTPException(
            status_code=409,
            detail="PSBT unrecognized in database"
        )

    #Get Data out of DB to compare target_address, amount, etc. with signed PSBT
    if psbt_db.get("psbt_state") != "COLD_STARTED":
        log.warning(f"Invalid broadcast state psbt_id={psbt_id}")
        raise HTTPException(
            status_code=409,
            detail="Invalid PSBT state for broadcast"
        )
    
    psbt_db['rail'] = "OPA_cold"
    psbt_db['psbt'] = psbt_signed 
    psbt_db = await create_psbt_msg(psbt_db)
    
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
        error_code=psbt_db.error_code,
    )


    #Check between DB and actual signed PSBT
    if signed_parsed.amount_sats != psbt_db.amount_sats or signed_parsed.target_address != psbt_db.target_address:
        raise HTTPException(status_code=409, detail="Signierte PSBT weicht vom DB-Eintrag ab")

    log.info(f"Broadcast request psbt_id={psbt_id} hash={signed_parsed.sha256}")

    try:
        #finalize
        rawtx_hex = psbt_finalize(psbt_signed)

    except Exception as e:
        log.exception("Failed to finalize PSBT")
        BROADCAST_TOTAL.labels(flow="cold", result="finalize_failed").inc()

        raise HTTPException(status_code=400, detail=f"finalization failed: {e}")

    try:
        #broadcast
        txid = broadcast_to_bitcoind(rawtx_hex)
        if not txid:
            raise RuntimeError("Bitcoind returned empty txid")
        
        BROADCAST_TOTAL.labels(flow="cold", result="ok").inc()

    except Exception as e:
        log.exception("Broadcast failed")
        BROADCAST_TOTAL.labels(flow="cold", result="broadcast_failed").inc()
        
        raise HTTPException(status_code=400, detail=f"broadcast failed: {e}")    

    #persist final state (optional tracking)
    psbt_db.state = "BROADCASTED"
    await asyncio.to_thread(
        insert_psbt, psbt_db
    )

    await asyncio.to_thread(
        archive_psbt, {
            **psbt_db.model_dump(),
            "final_tx": rawtx_hex,
            "txid": txid
        }
    )

    log.info(f"Broadcast success txid={txid}")

    #Löschen weiterer cold-Anfragen angekommen während cold-workflow (race condition)
    psbt_db_new = get_pending_PSBT()
    if psbt_db_new is not None and psbt_db_new.get("psbt_id") != psbt_id:
        await delete_psbt(psbt_db_new.get("psbt_id"))

    return {
        "txid": txid,
        "psbt_hash": signed_parsed.sha256,
    }