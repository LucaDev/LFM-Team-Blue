import asyncio, os, sys, json
from nats.aio.client import Client as NATS

async def main():
    subject = sys.argv[1]
    raw = open(sys.argv[2], "rb").read()
    json.loads(raw)                       # nur validieren, dass es JSON ist
    nc = NATS()
    await nc.connect(servers=[os.getenv("NATS_URL")])
    await nc.publish(subject, raw)
    await nc.flush()
    await nc.drain()

asyncio.run(main())