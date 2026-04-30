import os
from fastapi import FastAPI

app = FastAPI()

@app.get("/healthz")
def healthz():
    return {"ok": True}

@app.post("/api/v1/build/refill-psbt")
def build_refill_psbt(req: dict):
    # TODO: construct PSBT for cold->hot refill using UTXO set + fee estimator
    # Output should be base64 PSBT and stored under intent_id
    return {"status": "TODO", "req": req}