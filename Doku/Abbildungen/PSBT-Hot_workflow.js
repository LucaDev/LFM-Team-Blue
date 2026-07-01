flowchart TD

REQ["Externe Anfrage (BIP21-URI / PSBT)"]
REQ --> A7["Middleware: Intent anlegen + Dedup ueber ID"]
A7 --> DEC2{"PSBT oder Intent?"}
DEC2 --> A2["TX-Builder: walletcreatefundedpsbt"]
DEC2 --> A4["TX-Builder: walletcreatefundedpsbt"]
A2 --> A3["Bitcoin Core: UTXO-Auswahl, Change, Gebuehren"]
A3 --> A4["OPA: Betrag / Gebuehr / Netzwerk / Whitelist"]
A4 --> A5["Signer-VM Key A: signieren (WireGuard + HMAC)"]
A5 --> DEC{"Wallet?"}

DEC -->|"Hot / Sweep: PSBT 1/1"| H1["Bitcoin Core: finalisieren"]
H1 --> H2["Broadcast (Bitcoin Core)"]
H2 --> NET["Bitcoin-Netzwerk"]

DEC -->|"Refill aus Cold: PSBT 1/3"| C1["psbt_export.sh: 1/3-PSBT auf USB"]
C1 --> C2["Cold-Wallet-Workflow"]

%% Alle Schritte werden von der Middleware orchestriert (NATS-Events / HTTP)