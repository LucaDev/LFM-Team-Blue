import os
import json
import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from .models import PSBTModel, isModel

DB_HOST = os.getenv("POSTGRES_HOST", "postgres")
DB_PORT = int(os.getenv("POSTGRES_PORT", "5432"))
DB_USER = os.getenv("POSTGRES_USER", "")
DB_PASSWORD = os.getenv("POSTGRES_PASSWORD", "")
DB_NAME = os.getenv("POSTGRES_DB", "")

def conn():
    if not DB_USER or not DB_NAME:
        raise RuntimeError("Postgres credentials not configured")
    return psycopg.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        dbname=DB_NAME,
        row_factory=dict_row,
    )


#Wenn error auftritt, dass die DB zurückgerollt werden kann
def rollback():
    with conn() as c:
        c.rollback()

def _jsonb(v):
    return Jsonb(v.model_dump() if isModel(v) else v)


#wallet
def get_wallet(wallet_id: str):
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("""
                SELECT wallet_id, xpub, derivation_path, gap_limit, last_used_index, next_scan_index
                FROM btc.wallet
                WHERE wallet_id = %s
            """, (wallet_id,))
            return cur.fetchone()

    

def get_wallet_ids():
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("""
                SELECT wallet_id
                FROM btc.wallet
            """)
            return cur.fetchall()
       


def fetch_all(query: str, params: tuple = ()):
    with conn() as c:
        with c.cursor() as cur:
            cur.execute(query, params)
            return cur.fetchall()
        
def get_walletName(type: str) -> str:
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("""
                SELECT wallet_name
                FROM btc.wallet
                WHERE wallet_type = %s
                AND active = TRUE
            """, (type,))
            return [row["wallet_name"] for row in cur.fetchall()]

#One time pro wallet
def create_wallet(
    wallet_id: str,
    wallet_name: str,
    wallet_type: str,
    network: str,
    xpub: str | None,
    derivation_path: str | None,
    master_fingerprint: str | None,
    descriptor: str
):
    with conn() as c:
        with c.cursor() as cur:
            cur.execute(
                """
                INSERT INTO btc.wallet (
                    wallet_id,
                    wallet_name,
                    wallet_type,
                    network,
                    xpub,
                    derivation_path,
                    master_fingerprint,
                    descriptor
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (wallet_id)
                DO UPDATE SET
                    xpub = EXCLUDED.xpub,
                    derivation_path = EXCLUDED.derivation_path,
                    master_fingerprint = EXCLUDED.master_fingerprint
                """,
                (
                    wallet_id,
                    wallet_name,
                    wallet_type,
                    network,
                    xpub,
                    derivation_path,
                    master_fingerprint,
                    descriptor
                )
            )

        c.commit()

def archive_psbt(data: dict):
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("""
                INSERT INTO btc.psbt_archive (
                    psbt_id,
                    wallet_type,
                    network,
                    signed_psbt,
                    raw_tx,
                    txid,
                    source_address,
                    target_address,
                    amount_sats,
                    fee_sats,
                    fee_rate,
                    sha256,
                    meta
                )
                VALUES (
                    %s,%s,%s,%s,%s,%s,%s,%s,
                    %s,%s,%s,%s,%s
                )
            """, (
                data.get("psbt_id"),
                data.get("wallet_type"),
                data.get("network", "regtest"),
                data.get("psbt"),
                data.get("final_tx"),
                data.get("txid"),
                data.get("source_address"),
                data.get("target_address"),
                data.get("amount_sats"),
                data.get("fee_sats"),
                data.get("fee_rate"),
                data.get("sha256"),
                json.dumps(data.get("meta", {}))
            ))
        c.commit()

#State logging für psbts (unterscheidung zu intent möglcih, aber unnötig kompliziert)
def insert_psbt(psbt: PSBTModel):
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("""
                INSERT INTO btc.psbt (
                    psbt_id,
                    psbt_type,
                    psbt_state,
                    network,
                    amount_sats,
                    source_address,
                    target_address,
                    meta,
                    error_code
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """, (
                psbt.psbt_id,
                psbt.wallet_type,
                psbt.state,
                psbt.network,
                psbt.amount_sats,
                psbt.source_address,
                psbt.target_address,
                json.dumps(psbt.meta),
                json.dumps(psbt.error_code)
            ))
        c.commit()


def get_pending_PSBT():
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("""
                SELECT DISTINCT ON (psbt_id)
                    psbt_id,
                    psbt_type,
                    psbt_state,
                    network,
                    amount_sats,
                    source_address,
                    target_address,
                    meta
                FROM btc.psbt
                WHERE psbt_state = 'WAITING_HUMAN'
                ORDER BY psbt_id, id DESC;
            """)

            row = cur.fetchone()

    if not row:
        return None

    return {
        "psbt_id": row["psbt_id"],
        "wallet_type": row["psbt_type"],
        "state": row["psbt_state"],
        "network": row["network"],
        "amount_sats": row["amount_sats"],
        "source_address": row["source_address"],
        "target_address": row["target_address"],
        "meta": row["meta"],
    }


def get_psbt_byID(psbt_id: str):
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("""
                SELECT DISTINCT on (psbt_id)
                    psbt_id,
                    psbt_type,
                    psbt_state,
                    network,
                    amount_sats,
                    source_address,
                    target_address,
                    meta
                FROM btc.psbt
                WHERE psbt_id = %s
                ORDER BY psbt_id, id DESC
            """, (psbt_id,))

            row = cur.fetchone()

    if not row:
        return None

    return {
        "psbt_id": row["psbt_id"],
        "wallet_type": row["psbt_type"],
        "state": row["psbt_state"],
        "network": row["network"],
        "amount_sats": row["amount_sats"],
        "source_address": row["source_address"],
        "target_address": row["target_address"],
        "meta": row["meta"],
    }


def psbt_id_exists(psbt_id: str) -> bool:
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("""
                SELECT 1
                FROM btc.psbt
                WHERE psbt_id = %s
                LIMIT 1
            """, (psbt_id,))
            
            return cur.fetchone() is not None



def insert_opa_decision(
    psbt_id: str,
    policy_name: str,
    actor: str,
    action: bool,
    reasons: list,
    input_data: str,
    result: dict
):
    with conn() as c:
        with c.cursor() as cur:

            # 1. resolve internal psbt DB id
            if psbt_id != "refill_check":
                db_psbt_id = get_psbt_db_id(psbt_id)
                if db_psbt_id is None:
                    raise RuntimeError(f"psbt_id not found: {psbt_id}")
            else: db_psbt_id = psbt_id

            # 2. insert policy decision
            cur.execute("""
                INSERT INTO btc.opa_decision (
                    psbt_id,
                    policy_name,
                    actor,
                    allowed,
                    reasons,
                    input,
                    result
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s)
            """, (
                str(db_psbt_id),
                policy_name,
                actor,
                action,
                _jsonb(reasons),
                _jsonb(input_data),
                _jsonb(result)
            ))

        c.commit()

#Hilfsfunktion psbt_id zu letzter id (unique) für referenzen auflösen
def get_psbt_db_id(psbt_id: str) -> int | None:
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("""
                SELECT id
                FROM btc.psbt
                WHERE psbt_id = %s
                ORDER BY id DESC
                LIMIT 1
            """, (psbt_id,))
            row = cur.fetchone()
            return row["id"] if row else None
        

#Deduplication check, ob es psbt schon gab
def psbt_created_seen(psbt_id: str, state: str = "INTENT_CREATED") -> bool:
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("""
                SELECT 1
                FROM btc.psbt
                WHERE psbt_id = %s
                  AND psbt_state = %s
                LIMIT 1
            """, (psbt_id, state))
            return cur.fetchone() is not None