from fastapi import APIRouter
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response

from src.metrics import WAITING_HUMAN
from src.db import count_waiting_human

router = APIRouter()

@router.get("/healthz")
def healthz():
    return {"ok": True}

@router.get("/health")
async def health():
    return {
        "service": "middleware",
        "status": "ok"
    }

@router.get("/metrics") 
def metrics():
    try:
        WAITING_HUMAN.set(count_waiting_human())   # Zustands-Gauge beim Scrape aktualisieren
    except Exception:
        pass
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


