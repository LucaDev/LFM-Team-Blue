import os
import json
from fastapi import FastAPI
import asyncio
from nats.aio.client import Client as NATS
import logging


from .opa import opa_evaluate, check_walletBalance, handle_refillDecision
from src.com.btc_core import broadcast_to_bitcoind, psbt_finalize
from .signer import sign_psbt
from .txBuilder import handle_psbt_created, handle_psbt_failed, whitelist_check
from .logging_setup import setup_logging
from .models import create_psbt, create_psbt_msg, create_paymentIntent_msg
from src.com import payments, internal
from src.com.psbt import cleanup_refill, load_manual, refill_broadcast, save_psbt
from .db import archive_psbt, psbt_created_seen, insert_psbt
from src.com.wallets import import_wallet
from src.com.ntfy import notify
from .metrics import PSBT_SIGNED_TOTAL, BROADCAST_TOTAL, INTENTS_TOTAL


BITCOIN_NETWORK = os.getenv("BITCOIN_NETWORK", "regtest")
POLICY_SIGNER_URL = os.getenv("POLICY_SIGNER_URL", "http://policy-signer:8080")
NATS_URL = os.getenv("NATS_URL", "nats://nats:4222")

SERVICE_NAME = os.getenv("SERVICE_NAME", "middleware")
log = logging.getLogger(SERVICE_NAME)

nc = None


#API dateien /api
app = FastAPI()

app.include_router(payments.router)
app.include_router(internal.router)
    

############################################################################
@app.on_event("startup")
async def startup():

    #NATS setup
    global nc
    nc = await _connect_nats(NATS_URL)
    #In API state packen
    app.state.nc = nc

    setup_logging(SERVICE_NAME)

    async def wallet_import_handler(msg):
        metadata = json.loads(msg.data.decode())
        try:
            result = await import_wallet(metadata)

            await nc.publish("wallet.import.done", json.dumps(result).encode())
            log.info("wallet imported via NATS", extra={"wallet_id": result.get("wallet_id")})

        except Exception as e:
            log.exception("wallet import failed")
            await nc.publish("wallet.import.failed", json.dumps({"error": str(e)}).encode())


    #Init
    #Weiterleitung zu TX-builder
    async def intent_created_handler(msg):
        intent = await create_paymentIntent_msg(json.loads(msg.data.decode()))

        rail = intent.rail
        log.info(f"intent received: {intent.id} rail={rail}")

        #Deduplication of Tx (only when id send by vendor. wenn selsbtvergeben immer unique)
        if await asyncio.to_thread(psbt_created_seen, intent.id, "INTENT_CREATED"):
            log.info(f"Already seen: {intent.id} rail={rail}")
            return
            

        if rail in ("bip21", "manual"):
            psbt = await create_psbt(
                psbt_id=intent.id,
                wallet_type="hot",
                rail=intent.rail,
                psbt="",                                    #nach tx-builder
                network=intent.network,
                source_address="keyA",
                target_address=intent.target_address,
                amount_sats=intent.amount_sats,
                fee_sats=None,
                fee_rate=None,
                changepos=None,
                state="INTENT_CREATED",
                meta={
                    "rail": rail,
                },
                error_code={}
            )

            await asyncio.to_thread(
                insert_psbt, psbt
            )

            await nc.publish(
                "psbt.build.requested",
                intent.model_dump_json().encode()
            )

        else:
            log.error(f"unknown rail: {rail}")


    #Nach TX-Builder
    #Unerfolgreich    
    async def psbt_failed_handler(msg):
        data = json.loads(msg.data.decode())
        #Inkludiert nur logging
        await handle_psbt_failed(data)


    #Nach TX-builder
    #Erfolgreich
    #Weiterleitung zu Signer
    async def psbt_created_handler(msg):
        psbt = await create_psbt_msg(json.loads(msg.data.decode()))

        #Inkludiert nur logging
        await handle_psbt_created(psbt)

        if await opa_evaluate(psbt):
            if await whitelist_check(psbt.target_address, psbt.rail):
                #refill und hot-tx müssen gesigned werden
                #Weiterleitung zum Signer
                psbt_signed = await sign_psbt(psbt)
                if psbt_signed is None:
                    log.error("Signing failed, abort flow psbt_id=%s", psbt.psbt_id)
                    PSBT_SIGNED_TOTAL.labels(result="failed").inc()

                    return
                
                PSBT_SIGNED_TOTAL.labels(result="ok").inc()

                psbt.psbt = psbt_signed
                if psbt.wallet_type == "hot":
                    #Finalisierung
                    try:
                        rawtx_hex = await asyncio.to_thread(psbt_finalize, psbt_signed)

                        psbt.state = "FINALIZED"
                        await asyncio.to_thread(
                            insert_psbt, psbt
                        )
                        log.info("PSBT finalized successfully.")

                    except Exception as e:
                        log.exception(f"PSBT finalization failed: {e}")
                        BROADCAST_TOTAL.labels(flow="hot", result="finalize_failed").inc()

                        psbt.state = "FINALIZE_FAILED"
                        await asyncio.to_thread(insert_psbt, psbt)

                        await notify("Finalization failed", f"id={psbt.psbt_id}: {e}", priority="urgent", tags="rotating_light")
                        return

                    #Broadcast
                    try:
                        txid = await asyncio.to_thread(broadcast_to_bitcoind, rawtx_hex)
                        if not txid:
                            raise RuntimeError("Bitcoind returned no transaction id.")
                        
                        psbt.state = "BROADCASTED"
                        await asyncio.to_thread(
                            insert_psbt, psbt
                        )
                        log.info("Transaction broadcasted successfully. txid=%s", txid)
                        BROADCAST_TOTAL.labels(flow="hot", result="ok").inc()

                    except Exception as e:
                        log.exception(f"PSBT broadcast failed: {e}")
                        BROADCAST_TOTAL.labels(flow="hot", result="broadcast_failed").inc()

                        psbt.state = "BROADCAST_FAILED"
                        await asyncio.to_thread(insert_psbt, psbt)

                        await notify("Broadcast failed", f"id={psbt.psbt_id}: {e}", priority="urgent", tags="rotating_light")
                        return

                    #Archíving
                    await asyncio.to_thread(
                        archive_psbt, {
                            **psbt.model_dump(),
                            "final_tx": rawtx_hex,
                            "txid": txid
                        }
                    )
                    log.info("Broadcast completed")

                    decision = await check_walletBalance(psbt.source_address)
                    psbt_input = await handle_refillDecision(decision)
                    
                    
                    if psbt_input is not None:
                        intent = await create_paymentIntent_msg(psbt_input)
                        await nc.publish(
                            "psbt.build.requested",
                            intent.model_dump_json().encode()
                        )       

                elif psbt.wallet_type == "cold":
                    await save_psbt(psbt_signed, psbt.psbt_id)

                    psbt.state = "WAITING_HUMAN"
                    await asyncio.to_thread(
                        insert_psbt, psbt
                    )
                    log.info("Warten auf Operanten feur cold-worflow")

                    #Ntfy informieren
                    await notify("Cold-Refill nötig",
                    f"{psbt.amount_sats} sats -> {psbt.target_address} (id={psbt.psbt_id})",
                    priority="high", tags="warning,money")
                    

            else:
                await notify("Rejected request to not-whitelisted wallet, malicious request", f"id={psbt.psbt_id}", priority="urgent", tags="rotating_light")
                return
        

    #Initial
    await nc.subscribe(
        "intent.created",
        cb=intent_created_handler
    )

    #Nach TX-Builder
    await nc.subscribe(
        "psbt.created",
        cb=psbt_created_handler
    )

    await nc.subscribe(
        "psbt.failed",
        cb=psbt_failed_handler
    )

    await nc.subscribe(
        "wallet.import.requested", 
        cb=wallet_import_handler
    )

    await nc.subscribe(
        "refill.export.done",
        cb=cleanup_refill
    )
    await nc.subscribe(
        "refill.broadcast.requested",
        cb=refill_broadcast
    )

    async def psbt_submit_handler(msg):
        psbt_model = await load_manual(msg)
        if psbt_model is None:
            return
    
        await nc.publish("psbt.created", psbt_model.model_dump_json().encode())
        INTENTS_TOTAL.labels(rail="manual").inc()
        log.info("manual psbt submitted", extra={"psbt_id": psbt_model.psbt_id})

    await nc.subscribe(
        "psbt.submit.requested",
        cb=psbt_submit_handler
    )


@app.on_event("shutdown")
async def shutdown():
    global nc
    if nc:
        await nc.drain()

    log.info(SERVICE_NAME)

async def _connect_nats(url: str, attempts: int = 15, base: float = 1.0) -> NATS:
    nc = NATS()
    for i in range(attempts):
        try:
            await nc.connect(
                servers=[url],
                max_reconnect_attempts=-1,     # danach dauerhaft reconnecten
                reconnect_time_wait=2,
            )
            return nc
        except Exception as e:
            wait = min(base * (2 ** i), 30)
            log.warning("NATS connect failed (%s), retry in %ss", e, wait)
            await asyncio.sleep(wait)
    raise RuntimeError("NATS not reachable after retries")