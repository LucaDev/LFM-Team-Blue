import os
import httpx
import asyncio
import logging
from uuid import uuid4 
from decimal import Decimal, ROUND_HALF_UP

from .db import get_pending_PSBT, insert_psbt, insert_opa_decision, psbt_id_exists, get_walletName, sats_perTime
from .metrics import OPA_DECISIONS_TOTAL, VELOCITY_BLOCK_TOTAL, REFILL_TOTAL, HOT_BALANCE_BTC
from .models import PSBTModel
from src.com.ntfy import notify
from .signer import delete_psbt
from src.com.btc_core import get_walletBalance

OPA_URL = os.getenv("OPA_URL", "http://opa:8181")
SERVICE_NAME = os.getenv("SERVICE_NAME", "middleware")
log = logging.getLogger(SERVICE_NAME)


async def send_to_opa(psbt: PSBTModel, spent_today: int = 0) -> dict:
    payload = {"input": parseOPA_PSBT(psbt, spent_today)}

    log.info(
        "sending to OPA",
        extra={
            "payload": payload
        }
    )

    async with httpx.AsyncClient(timeout=3.0) as client:
        resp = await client.post(
            f"{OPA_URL}/v1/data/policy/hot/decision",
            json=payload,
        )
        resp.raise_for_status()

        raw = resp.json().get("result", {})
        
        # normalize reasons into list
        reasons_raw = raw.get("reasons", {})
        
        # normalize reasons into list
        if isinstance(reasons_raw, dict):
            reasons = [k for k, v in reasons_raw.items() if v]
        elif isinstance(reasons_raw, list):
            reasons = reasons_raw
        else:
            reasons = []

        return {
            "allow": raw.get("allow", False),
            "reasons": reasons,
            "limits": raw.get("limits", {}),
        }
    
def parseOPA_PSBT(psbt: PSBTModel, spent_today: int = 0) -> dict:
    return {
        "psbt_id": psbt.psbt_id,
        "wallet_type": psbt.wallet_type,
        "rail": psbt.rail,
        "psbt": psbt.psbt,
        "network": psbt.network,
        "target_address": psbt.target_address,
        "source_address": psbt.source_address,

        "amount_sats": psbt.amount_sats,
        "fee_sats": psbt.fee_sats,
        "fee_rate": psbt.fee_rate,
        "spent_today": spent_today,
    }
    

async def opa_evaluate(psbt: PSBTModel) -> bool:

    spent_today = 0
    if psbt.rail not in ("OPA_hot", "OPA_cold"):                    # DB nur bei Zahlungen anfragen
        spent_today = await asyncio.to_thread(sats_perTime, 24)

    #Weiterleitung zu OPA bei hot-tx, nicht benötigt für refill (mensch)
    decision = await send_to_opa(psbt, spent_today)

    allowed = decision.get("allow", False)
    reasons = decision.get("reasons", [])

    OPA_DECISIONS_TOTAL.labels(result="allow" if allowed else "deny").inc()
    if "daily limit exceeded" in reasons:
        VELOCITY_BLOCK_TOTAL.inc()

    #DB logging
    await asyncio.to_thread(
        insert_opa_decision,
        psbt_id=psbt.psbt_id,
        policy_name="policy.hot.tx",
        actor="middleware",
        action=allowed,
        reasons=reasons,
        input_data=psbt,
        result = decision
    )

    #Fehlschlagen OPA Prüfung
    if not allowed:
        psbt.state = "OPA_REJECTED"
        psbt.error_code = psbt.error_code or reasons
        await asyncio.to_thread(
            insert_psbt, psbt
        )

        log.info(
            "not permitted",
            extra={
                "payload": psbt
            }
        )

        await notify("OPA rejected request", f"id={psbt.psbt_id}, reasons: {reasons}", priority="urgent", tags="rotating_light")
        return False

    psbt.state = "OPA_APPROVED"
    await asyncio.to_thread(
        insert_psbt, psbt
    )
    log.info(
        "Permitted",
        extra={
            "payload": psbt
        }
    )
    return True


async def check_walletBalance(wallet_name: str):
    balance = get_walletBalance(wallet_name)
    HOT_BALANCE_BTC.set(float(balance))

    payload = {"input": {
        "balance": balance
    }}

    log.info(
        "sending wallet balance to OPA",
        extra={"payload": payload}
    )

    async with httpx.AsyncClient(timeout=3.0) as client:
        resp = await client.post(
            f"{OPA_URL}/v1/data/policy/hot/limits/output",
            json=payload,
        )
        resp.raise_for_status()

        raw = resp.json().get("result", {})
        execution = raw.get("execution", {})

        return {
            "action": raw.get("action"),
            "balance": raw.get("balance"),
            "amount": raw.get("amount", 0),
            "target": raw.get("target", 0),
            "risk_score": raw.get("risk_score", 0),
            "reason": raw.get("reason"),

            "execution": execution,
        }
    
async def handle_refillDecision(decision: dict):
    action = decision.get("action")
    amount = decision.get("amount", 0)
    execution = decision.get("execution", {})
    reason = decision.get("reason", {})

    REFILL_TOTAL.labels(action=action).inc()
    
    if action == "hold":
        action_allowed = False
    else:
        action_allowed = True

    log.info("OPA decision received", extra=decision)
    await asyncio.to_thread(
        insert_opa_decision,
        psbt_id="refill_check",
        policy_name="policy.hot.limits",
        actor="middleware",
        action=action_allowed,
        reasons=reason,
        input_data=decision.get("balance"),
        result = decision
    )

    amount_btc = Decimal(str(amount))
    amount_sats = int(amount_btc * Decimal("100000000"))


    if action == "hold":
        log.info("no fund swap required")

        #Refill PSBT löschen, da OPA balance zu hoch
        pending = get_pending_PSBT()
        if pending is not None:
            log.info("deleting old refill PSBT", extra={"psbt_id": pending.get("psbt_id")})
            await delete_psbt(pending["psbt_id"])   # COLD_STOPPED + unlink
        return None

    intent_id = ""
    while True:
        intent_id = str(uuid4())
        exists = await asyncio.to_thread(psbt_id_exists, intent_id)
        if not exists:
            break

    if action == "hot_to_cold":
        source_address = get_walletName("hot")[0]
        target_address = get_walletName("cold")[0]
        type = "hot-tx"
        rail = "OPA_hot"

        #Refill PSBT löschen, da OPA balance zu hoch
        pending = get_pending_PSBT()
        if pending is not None:
            log.info("deleting old refill PSBT", extra={"psbt_id": pending.get("psbt_id")})
            await delete_psbt(pending["psbt_id"])   # COLD_STOPPED + unlink

    elif action == "cold_to_hot":
        source_address = get_walletName("cold")[0]
        target_address = get_walletName("hot")[0]
        type = "refill"
        rail = "OPA_cold"

    else:
        raise ValueError(f"Unknown action: {action}")
    
    return{
        "id": intent_id,
        "type": type,
        "rail": rail,
        "network": "regtest",
        "source_address": source_address,
        "target_address": target_address,
        "amount_sats": amount_sats,
        "meta": execution
    }