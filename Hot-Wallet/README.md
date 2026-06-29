# Hot-Wallet – Automatisierter Hot-Flow & Air-gapped Cold-Refill

---

## Ziel

Dieses Repository enthält den Service-Stack für den `btc-hot` Teil des Bitcoin-Custody-Setups:

- automatisiertes Signieren und Broadcasten ausgehender Hot-Wallet-Transaktionen, gesteuert über eine Policy-Engine (OPA)
- automatische Erkennung von Über-/Unterdeckung der Hot-Wallet und Erzeugung der entsprechenden Refill-Transaktionen
- Übergabe an den air-gapped Cold-Signing-Workflow (Sparrow/Key B/Key C), sobald eine menschliche Freigabe nötig ist

Der Stack ist bewusst in containerisierte Services aufgeteilt und kommuniziert intern über NATS. Die eigentliche Signatur der Hot-Transaktionen erfolgt **nicht** in diesem Stack, sondern auf einer separaten Signer-VM, die ausschließlich über WireGuard + HMAC erreichbar ist.

---

## Architektur-Überblick

```
                         ┌────────────────────────┐
 externe Anfrage  ─────▶ │  middleware (FastAPI)  │
 (BIP21 / PSBT)          └───────────┬─────────────┘
                                     │ NATS
                          ┌──────────┴───────────┐
                          │                       │
                 intent.created            psbt.created / psbt.failed
                          │                       │
                          ▼                       │
                ┌──────────────────┐              │
                │   tx-builder     │──────────────┘
                │ (PSBT erzeugen)  │
                └──────────────────┘
                          │
                          ▼
                ┌──────────────────┐        ┌─────────────────┐
                │       opa        │◀──────▶│   middleware     │
                │ (Policy-Engine)  │        │  (Entscheidung)  │
                └──────────────────┘        └─────────┬────────┘
                                                       │ WireGuard + HMAC
                                                       ▼
                                             ┌────────────────────┐
                                             │   Signer-VM         │
                                             │ (air-gapped, extern)│
                                             └─────────┬──────────┘
                                                       │ signierte PSBT
                                                       ▼
                                             ┌────────────────────┐
                                             │   btc-core (RPC)   │
                                             │ finalize+broadcast │
                                             └────────────────────┘
```

Zusätzlich existiert der manuelle Cold-Refill-Pfad: Sinkt die Hot-Wallet unter den definierten Schwellenwert, wird eine Refill-PSBT erzeugt und über das dedizierte USB-Wechselmedium an den air-gapped Cold-Workflow (Sparrow, Key B/Key C) übergeben – analog zum bestehenden Air-gapped-PSBT-Runbook.

---

## Komponenten und Verantwortung

### `middleware` (FastAPI, Port 8080)

Zentrale Orchestrierung. Aufgaben:

- nimmt externe Zahlungsanfragen entgegen (`POST /api/v1/request/bip21`, `POST /api/v1/request/psbt`)
- verwaltet die Wallet-Registrierung in Bitcoin Core (`POST /api/v1/importWallet`)
- fragt OPA für jede zu signierende PSBT um Entscheidung an
- prüft die Zieladresse gegen die registrierten Hot-/Cold-/External-Wallets (Whitelist)
- leitet zu signierende PSBTs HMAC-authentifiziert an die Signer-VM weiter
- finalisiert und broadcastet signierte Transaktionen über `btc-core`
- persistiert Zustände, Policy-Entscheidungen und abgeschlossene Transaktionen in PostgreSQL
- stellt den Cold-Refill-Workflow bereit (`GET /api/v1/request/psbt`, `POST /api/v1/request/broadcast`), über den der Operator die PSBT auf das USB-Wechselmedium exportiert bzw. die signierte PSBT wieder einliest

### `tx-builder`

Reagiert auf NATS-Intents (`psbt.build.requested`) und baut daraus über Bitcoin Core (`walletcreatefundedpsbt`) die eigentliche PSBT, inklusive Gebührenschätzung passend zum jeweiligen Risiko-Score der Refill-Entscheidung. Meldet Erfolg (`psbt.created`) oder Fehlschlag (`psbt.failed`) zurück an `middleware`. Stellt zusätzlich `/healthz` und `/metrics` (Prometheus) bereit.

### `opa` (Open Policy Agent)

Policy-Engine, geladen mit zwei Policy-Paketen:

- `policy.hot` (`hot.rego`) – Allow/Deny-Entscheidung für jede einzelne Transaktion: erlaubtes Netzwerk, Mindest-/Maximalbetrag, Fee-Grenzen, Pflichtfeld `sha256`
- `hot.limits` (`limits.rego`) – berechnet aus dem aktuellen Hot-Wallet-Saldo, ob und in welche Richtung ein Refill nötig ist (`hot_to_cold` / `cold_to_hot` / `hold`), inklusive Risiko-Score und empfohlener Bestätigungstiefe

Limits, Schwellenwerte und erlaubte Netzwerke liegen in `services/opa/data/data.json` und werden zur Laufzeit per `--watch` neu geladen.

### `btc-core`

Eigener, aus dem Quellcode gebauter `bitcoind` (Tag `v31.0`), für die lokale Regtest-Umgebung. Kein vorgefertigtes Docker-Image, sondern Multi-Stage-Build direkt aus dem offiziellen Bitcoin-Core-Repository. Verwaltet die Wallets `keyA` (Hot) und `cold-multi` (Cold, watch-only) sowie die Test-Wallets `wallet1`–`wallet3` zur Simulation von Zahlungsverkehr.

### `postgres`

Persistiert drei Bereiche (`services/postgres/001_psbt.sql`):

- `btc.wallet` – registrierte Wallets inkl. xpub/Descriptor/Fingerprint
- `btc.psbt` – Zustandsverlauf jeder PSBT über den gesamten Lebenszyklus
- `btc.opa_decision` – jede Policy-Entscheidung inklusive Input/Output, vollständig nachvollziehbar
- `btc.psbt_archive` – abgeschlossene, broadcastete Transaktionen mit Rohdaten, TXID und Hash

### `nats`

Event-Bus zwischen `middleware` und `tx-builder`. Relevante Subjects:

- `intent.created` – neue Zahlungsabsicht
- `psbt.build.requested` – Auftrag an `tx-builder`
- `psbt.created` / `psbt.failed` – Ergebnis von `tx-builder` zurück an `middleware`

`nats-box` ist als reines Debug-Werkzeug zum manuellen Publizieren/Abonnieren von Subjects eingebunden.

### Signer-VM (air-gapped, nicht Teil dieses Repos)

Hält den Hot-Signing-Key. Erreichbar ausschließlich über:

- einen WireGuard-Tunnel (`10.10.0.1` Hot-System ↔ `10.10.0.2` Signer-VM)
- HMAC-signierte Requests (SHA-256, mit Timestamp + Nonce gegen Replay)

Die Einrichtung dieses Tunnels und der Austausch des HMAC-Secrets erfolgt einmalig über das USB-Wechselmedium (siehe unten).

---

## Repository-Struktur

```text
Hot-Wallet/
  docker-compose.yaml

  services/
    middleware/            # FastAPI-Orchestrierung
    tx-builder/             # PSBT-Erstellung
    opa/                    # Policies (hot.rego, limits.rego) + data.json
    postgres/                # Schema (001_psbt.sql)
    btc-core/                # Eigener bitcoind-Build + Wallet-Init
    ntfy/                    # Notification-Schnittstelle (Platzhalter, s.u.)
    shared/                  # gemeinsame Health-Check-Helfer

  scripts/
    ops/
      setup/                 # WireGuard- und Wallet-Setup (einmalig)
      refill/                 # USB-Export/Broadcast für den Cold-Refill-Workflow
    testing/                  # Smoke-Tests, Regtest-Geldsimulation, NATS-Testpayloads
```

---

## Setup

### Voraussetzungen

- Docker und Docker Compose
- `jq`, `curl` auf allen Hosts, die mit dem USB-Wechselmedium arbeiten
- WireGuard-Tools (`wg`, `wg-quick`) auf Hot-System und Signer-VM
- Ein dediziertes USB-Wechselmedium mit Label `USB`

### 1. Stack starten

```bash
docker compose up -d
```

Dies startet `postgres` (inkl. Schema-Migration), `nats`, `opa`, `btc-core`, `tx-builder` und `middleware`.

### 2. Bitcoin-Core-Wallets initialisieren (einmalig, regtest)

```bash
bash services/btc-core/wallets/wallet_init_oneTime.sh
```

Erzeugt `wallet1`–`wallet3` und exportiert deren Descriptoren nach `services/btc-core/wallets/*.descriptors.json`, damit bei jedem Neustart dieselben Adressen verwendet werden.

### 3. WireGuard-Tunnel zur Signer-VM einrichten

Auf dem Hot-System:

```bash
sudo scripts/ops/setup/wg_setup.sh
sudo scripts/ops/setup/wgPeer_export.sh
```

Letzteres schreibt den öffentlichen Schlüssel des Hot-Systems auf das eingelegte USB-Medium (`communication/wireguard/wireguard.wallet.json`).

Auf der Signer-VM wird dieselbe JSON-Datei eingelesen und der Peer dort eingetragen (Gegenstück, nicht Teil dieses Repos).

Anschließend, sobald die Signer-VM ihrerseits `wireguard.signer.json` sowie das HMAC-Secret auf dem Medium hinterlegt hat:

```bash
sudo scripts/ops/setup/wgHMAC_import.sh
```

Dies aktiviert den WireGuard-Peer auf dem Hot-System und legt das HMAC-Secret unter `middleware_data/secrets/` ab.

### 4. Wallets in der Middleware registrieren

```bash
bash scripts/ops/setup/wallet_import.sh
python3 scripts/ops/setup/whiteWallet.py
```

Liest Hot-/Cold-Wallet-Metadaten vom USB-Medium bzw. lokale Descriptor-Dateien und registriert sie über `POST /api/v1/importWallet` in der Middleware (inkl. Eintrag in Bitcoin Core und PostgreSQL).

---

## Transaktionsprozess

### Hot-Flow (automatisiert)

1. Externe Anfrage trifft via `POST /api/v1/request/bip21` oder `/psbt` auf `middleware` ein.
2. `middleware` veröffentlicht `intent.created`, `tx-builder` baut daraus die PSBT.
3. `middleware` fragt `opa` (`policy.hot`) nach Freigabe.
4. Bei Freigabe wird die Zieladresse gegen die registrierten Wallets geprüft (`whitelist_check`).
5. Die PSBT wird HMAC-signiert an die Signer-VM übergeben und dort signiert zurückgegeben.
6. `middleware` finalisiert die PSBT über `btc-core` (`finalizepsbt`) und broadcastet (`sendrawtransaction`).
7. Nach erfolgreichem Broadcast wird der aktuelle Hot-Wallet-Saldo erneut gegen `hot.limits` geprüft; bei Bedarf wird automatisch ein Refill-Intent erzeugt.

### Cold-Refill-Flow (air-gapped, manuell)

1. `opa` (`hot.limits`) erkennt Unterdeckung der Hot-Wallet und gibt `cold_to_hot` mit empfohlenem Betrag zurück.
2. `tx-builder` erstellt die Refill-PSBT; `middleware` legt sie als `WAITING_HUMAN` ab.
3. Operator exportiert die PSBT auf das USB-Medium:

   ```bash
   sudo API_BASE="http://localhost:8080" scripts/ops/refill/psbt_export.sh
   ```

   Das Skript verweigert den Export, falls bereits eine unbestätigte PSBT auf dem Medium liegt (Single-Transaction-Regel).

4. Der weitere Ablauf folgt dem bestehenden Air-gapped-PSBT-Runbook: Import in Sparrow auf Key B (und optional Key C), manuelle Prüfung von Zieladresse, Betrag und Gebühr, Signatur, Export als `appr.<psbt_id>.psbt`.
5. Operator liest die signierte PSBT zurück ein:

   ```bash
   sudo API_BASE="http://localhost:8080" scripts/ops/refill/psbt_broadcast.sh
   ```

   `middleware` finalisiert und broadcastet die Transaktion und archiviert sie in `btc.psbt_archive`.

---

## Policies (OPA)

| Policy | Datei | Zweck |
|---|---|---|
| `policy.hot` | `services/opa/policies/hot.rego` | Allow/Deny pro Transaktion (Netzwerk, Betrag, Fee-Grenzen, Pflichtfelder) |
| `hot.limits` | `services/opa/policies/limits.rego` | Refill-Logik anhand des aktuellen Hot-Wallet-Saldos |
| Daten | `services/opa/data/data.json` | Schwellenwerte, Limits, erlaubte Netzwerke |

Änderungen an `data.json` oder den `.rego`-Dateien werden vom laufenden OPA-Container automatisch übernommen (`--watch`).

---

## Testing / Lokale Simulation

Der Ordner `scripts/testing/` enthält ein vollständiges Smoke-Test-Set für die Regtest-Umgebung:

```bash
bash scripts/testing/btc-core/load_wallets.sh      # Wallets laden, Blöcke minen, initial befüllen
bash scripts/testing/btc-core/simMoney.sh           # Normale Geldbewegung simulieren
bash scripts/testing/btc-core/simMoney_refill.sh    # Hot-Wallet unter Mindestbestand bringen
bash scripts/testing/btc-core/simMoney_save.sh      # Hot-Wallet über Maximalbestand bringen

python3 scripts/testing/send_intent_API.py          # BIP21- und PSBT-Flow über die HTTP-API anstoßen
bash scripts/testing/send_intent_nats.sh            # Verschiedene OPA-Deny-/Allow-Fälle direkt über NATS testen
```

`scripts/testing/batch.sh` fasst Wallet-Setup, Geldsimulation und API-Test zu einem End-to-End-Lauf zusammen.

---

## Bekannter Stand / offene Punkte

- `services/ntfy/` ist als Schnittstelle für die Operator-Benachrichtigung vorgesehen, aber die eigentliche Server-Implementierung ist noch nicht im Repository enthalten.
- Im Repository liegen zusätzlich ein älteres `HOT-WALLET-RUNBOOK.md` sowie Vorversionen einzelner Skripte (`psbt-export`, `psbt-broadcast` ohne Dateiendung) aus einer früheren Kubernetes/Talos-Architektur. Maßgeblich für den aktuellen Stand sind `docker-compose.yaml` und die in diesem Dokument referenzierten `*.sh`-Skripte.
- Die Migration auf das NixOS-Basissystem (inkl. Docker-Betrieb ohne `sudo`) ist als nächster Schritt vorgesehen und noch nicht Teil dieses Repositorys.
