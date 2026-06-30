%%{init: {"flowchart": {"defaultRenderer": "elk"}}}%%
flowchart TB

subgraph HOT["Vertrauenszone 1 - Hot / Basis-System (Internet-exponiert)"]
  MW["Middleware"]
  TXB["TX-Builder"]
  BC["Bitcoin Core"]
  NATS["NATS Event-Bus"]
  OPA["OPA"]
  PG["PostgreSQL (btc-DB)"]

  MW ---|"HTTP: Policy"| OPA
  MW ---|"SQL"| PG
  MW ---|"NATS"| NATS
  TXB ---|"NATS"| NATS
  MW ---|"RPC"| BC
  TXB ---|"RPC"| BC
end

subgraph SIGN["Vertrauenszone 2 - Signer-VM Key A (gehaertet, nur via WireGuard)"]
  RP["Reverse-Proxy (WG 10.10.0.2)"]
  KA["Signer (Key A)"]
  PGS["PostgreSQL (Dedup-IDs)"]
  TPM["TPM (PCR-versiegelt)"]

  RP ---|"internes Docker-Netz"| KA
  KA ---|"SQL"| PGS
  KA ---|"entsiegelt Key A"| TPM
end

subgraph COLD["Vertrauenszone 3 - Cold (Air-Gapped)"]
  KB["Key-B-VM: Koordinator + Watch-Only + Key B"]
  KC["Key-C-VM (Recovery)"]
end

USB{{"USB-Medium (genau 1 PSBT)"}}

MW ---|"WireGuard + HMAC"| RP
MW -.->|"PSBT Export/Import"| USB
USB -.->|"PSBT (Umstecken)"| KB
USB -.->|"nur Recovery"| KC