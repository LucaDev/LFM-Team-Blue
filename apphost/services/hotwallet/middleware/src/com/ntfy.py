import os, base64, httpx, logging
NTFY_URL      = os.getenv("NTFY_URL")
NTFY_TOKEN    = os.getenv("NTFY_TOKEN", "")
NTFY_USER     = os.getenv("NTFY_USER", "")
NTFY_PASSWORD = os.getenv("NTFY_PASSWORD", "")
log = logging.getLogger(os.getenv("SERVICE_NAME", "middleware"))

async def notify(title: str, message: str, priority: str = "default", tags: str = ""):
    if not NTFY_URL:
        return
    headers = {"Title": title, "Priority": priority, "Tags": tags}
    if NTFY_TOKEN:
        headers["Authorization"] = f"Bearer {NTFY_TOKEN}"
    elif NTFY_USER:
        # apphost-eigener ntfy-Dienst nutzt Basic-Auth-Benutzer statt Access-Token
        basic = base64.b64encode(f"{NTFY_USER}:{NTFY_PASSWORD}".encode()).decode()
        headers["Authorization"] = f"Basic {basic}"
    try:
        async with httpx.AsyncClient(timeout=5.0) as c:
            await c.post(NTFY_URL, content=message.encode(), headers=headers)
    except Exception:
        log.exception("ntfy notify failed")  