import os
import hashlib
from base64 import b64decode
from fastapi import FastAPI, HTTPException
import httpx

try:
    import boto3
except ImportError:
    boto3 = None

try:
    from embit.psbt import PSBT
    from embit.transaction import Transaction
    from embit import ec
except ImportError:
    PSBT = None
    Transaction = None
    ec = None

app = FastAPI()

OPA_URL = os.getenv("OPA_URL", "http://opa.btc-hot.svc.cluster.local:8181")
HOT_SIGNING_PUBKEY = os.getenv("HOT_SIGNING_PUBKEY", "")
SIGNER_BACKEND = os.getenv("SIGNER_BACKEND", "soft").lower()
SIMULATE_SIGNING = os.getenv("SIMULATE_SIGNING", "true").lower() == "true"



@app.get("/healthz")
def healthz():
    return {"ok": True}


async def opa_check(policy_input: dict) -> dict:
    if not OPA_URL:
        raise HTTPException(500, "OPA_URL not configured")
    async with httpx.AsyncClient(timeout=10.0) as c:
        r = await c.post(f"{OPA_URL}/v1/data/policy/hot", json={"input": policy_input})
        r.raise_for_status()
        return r.json().get("result", {})


def double_sha256(data: bytes) -> bytes:
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()


def sign_with_aws_kms(digest: bytes) -> bytes:
    if boto3 is None:
        raise RuntimeError("boto3 is required for AWS KMS signing")
    kms_client = boto3.client("kms", region_name=os.getenv("AWS_REGION"))
    response = kms_client.sign(
        KeyId=HOT_SIGNING_KEY,
        Message=digest,
        MessageType="DIGEST",
        SigningAlgorithm="ECDSA_SHA_256",
    )
    return b64decode(response["Signature"])


def sign_psbt_with_aws_kms(psbt_base64: str) -> str:
    if PSBT is None or ec is None:
        raise RuntimeError("embit is required for PSBT signing")
    if not HOT_SIGNING_KEY:
        raise RuntimeError("HOT_SIGNING_KEY must contain AWS KMS KeyId")
    if not HOT_SIGNING_PUBKEY:
        raise RuntimeError("HOT_SIGNING_PUBKEY must be set")

    psbt_bytes = b64decode(psbt_base64)
    psbt = PSBT.parse(psbt_bytes)

    # Assume we have the private key in KMS, sign all inputs that need signing
    # This is a simplified example; in reality, you'd need to know which inputs to sign
    for idx, inp in enumerate(psbt.inputs):
        if inp.witness_utxo:  # Assuming P2WPKH or similar
            sighash = psbt.sighash(idx, sighash_type=1)  # SIGHASH_ALL
            digest = hashlib.sha256(sighash).digest()
            signature_der = sign_with_aws_kms(digest)
            # Convert DER to compact format if needed, but for simplicity, assume DER
            # embit expects compact sig, so convert
            r, s = ec.ECPubKey().parse_sig(signature_der)
            compact_sig = r.to_bytes(32, 'big') + s.to_bytes(32, 'big')
            inp.partial_sigs[bytes.fromhex(HOT_SIGNING_PUBKEY)] = compact_sig  # Use pubkey as key

    # Finalize PSBT
    psbt.finalize()
    return psbt.serialize().hex()


def sign_with_backend(unsigned_psbt_base64: str) -> str:
    if SIGNER_BACKEND == "aws-kms":
        return sign_psbt_with_aws_kms(unsigned_psbt_base64)
    elif SIGNER_BACKEND == "soft":
        # Placeholder software fallback: no real key material used.
        return unsigned_psbt_base64
    else:
        raise RuntimeError(f"Unsupported signer backend: {SIGNER_BACKEND}")


@app.post("/api/v1/sign")
async def sign(req: dict):
    unsigned_psbt_base64 = req.get("unsigned_psbt_base64")
    request_id = req.get("request_id")
    tx_hash = req.get("tx_hash")
    policy_input = req.get("policy_input") or {}

    if not unsigned_psbt_base64:
        raise HTTPException(400, "unsigned_psbt_base64 required")
    if not request_id:
        raise HTTPException(400, "request_id required")
    if not tx_hash:
        raise HTTPException(400, "tx_hash required")

    result = await opa_check(policy_input)
    if not result.get("allow", False):
        reasons = result.get("reasons", [])
        raise HTTPException(403, {"allowed": False, "reasons": reasons})

    if SIGNER_BACKEND == "soft":
        if SIMULATE_SIGNING:
            return {"signed_psbt_base64": unsigned_psbt_base64}
        raise HTTPException(503, "soft signing disabled")

    try:
        signed_psbt_base64 = sign_with_backend(unsigned_psbt_base64)
    except NotImplementedError as exc:
        raise HTTPException(501, str(exc))
    except Exception as exc:
        raise HTTPException(500, f"signing backend error: {exc}")

    return {"signed_psbt_base64": signed_psbt_base64}
