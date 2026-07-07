---
config:
  layout: elk
---
flowchart TB
    REQ["Externe Anfrage<br>POST /request/bip21 | /psbt"] --> MW["Middleware (Hot):<br>Intent + Dedup"]
    MW -- "bip21:<br>NATS psbt.build.requested" --> TB["TX-Builder:<br>walletcreatefundedpsbt"]
    MW -- fertige PSBT --> CHK["Middleware:<br>Whitelist + OPA"]
    TB -- "NATS psbt.created" --> CHK
    CHK -- POST /sign<br>WireGuard + HMAC --> SG["Signer (Key A):<br>Velocity-Cap, TPM, Signatur"]
    SG -- "Hot-PSBT: 1/1" --> FIN["Bitcoin Core:<br>finalisieren + broadcasten"]
    FIN --> NET["Bitcoin-<br>Netzwerk"]
    SG -- "Cold-PSBT: 1/3<br>WAITING_HUMAN" --> CW["ntfy-Alarm an Operator,<br>psbt_export.sh → Cold-Signierungs-Prozess"]
    FIN -- "getbalances →<br>OPA hot.limits" --> BAL{"hold | hot_to_cold |<br>cold_to_hot"}
    BAL -. neuer interner Intent<br>(Rail OPA_hot / OPA_cold) .-> TB