# Hot-Wallet – Automatisierter Hot-Flow & Air-gapped Cold-Refill

***

## Ziel

Dieses Repository enthält den Service-Stack für den `btc-hot` Teil des Bitcoin-Custody-Setups:

- automatisiertes Signieren und Broadcasten ausgehender Hot-Wallet-Transaktionen, gesteuert über eine Policy-Engine (OPA)
- ein manueller Operator-Pfad, über den eine eigene Hot-Transaktion (Betrag + Adresse oder fertige PSBT) ausgelöst werden kann
- automatische Erkennung von Über-/Unterdeckung der Hot-Wallet und Erzeugung der entsprechenden Refill-Transaktionen
- Übergabe an den air-gapped Cold-Signing-Workflow (Sparrow/Key B/Key C), sobald eine menschliche Freigabe nötig ist

Der Stack ist bewusst in containerisierte Services aufgeteilt und kommuniziert intern über NATS. Die eigentliche Signatur der Hot-Transaktionen erfolgt **nicht** in diesem Stack, sondern auf einer separaten Signer-VM, die ausschließlich über WireGuard + HMAC erreichbar ist.

***

## Architektur-Überblick

```
                         ┌────────────────────────┐
 externe Anfrage  ─────▶ │  middleware (FastAPI)  │
 (BIP21 / PSBT)          └───────────┬─────────────┘
 Operator (manual)                   │ NATS (authentifiziert)
 X-Operator-Token          ┌─────────┴───────────┐
                           │                       │
                  intent.created           psbt.created / psbt.failed
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
                                              │ TPM + Velocity-Cap  │
                                              └─────────┬──────────┘
                                                        │ signierte PSBT
                                                        ▼
                                              ┌────────────────────┐
                                              │   btc-core (RPC)   │
                                              │ finalize+broadcast │
                                              └────────────────────┘
```

Zusätzlich existiert der manuelle Cold-Refill-Pfad: Sinkt die Hot-Wallet unter den definierten Schwellenwert, wird eine Refill-PSBT erzeugt und über das dedizierte USB-Wechselmedium an den air-gapped Cold-Workflow (Sparrow, Key B/Key C) übergeben – analog zum bestehenden Air-gapped-PSBT-Runbook.

***

## Komponenten und Verantwortung

***

### `middleware` (FastAPI, Port 8080)

Zentrale Orchestrierung. Aufgaben:
* nimmt externe Zahlungsanfragen entgegen (`POST /api/v1/request/bip21`, `POST /api/v1/request/psbt`)
* schaltet über den Header `X-Operator-Token` den manuellen Operator-Pfad frei (Whitelist-Bypass, s.u.)
* fragt OPA für jede zu signierende PSBT um Entscheidung an (Betrags-, Fee- und Daily-Cap-Prüfung)
* prüft die Zieladresse gegen die registrierten Hot-/Cold-/External-Wallets (Whitelist)
* leitet zu signierende PSBTs HMAC-authentifiziert an die Signer-VM weiter
* finalisiert und broadcastet signierte Transaktionen über `btc-core`
* gleicht die signierte Cold-PSBT vor dem Broadcast gegen den DB-Eintrag (Betrag/Zieladresse) ab
* persistiert Zustände, Policy-Entscheidungen und abgeschlossene Transaktionen in PostgreSQL
* stellt den Cold-Refill-Workflow bereit (`GET /api/v1/request/psbt`, `POST /api/v1/request/broadcast/{psbt_id}`), über den der Operator die PSBT auf das USB-Wechselmedium exportiert bzw. die signierte PSBT wieder einliest
* registriert Wallets ausschließlich über NATS (`wallet.import.requested`) – ein öffentlicher HTTP-Import-Endpoint existiert **nicht**
* stellt `/healthz`, `/health` und `/metrics` (Prometheus) bereit

***

### `tx-builder`

Reagiert auf NATS-Intents (`psbt.build.requested`) und baut daraus über Bitcoin Core (`walletcreatefundedpsbt`) die eigentliche PSBT, inklusive Gebührenschätzung passend zum jeweiligen Risiko-Score der Refill-Entscheidung. Meldet Erfolg (`psbt.created`) oder Fehlschlag (`psbt.failed`) zurück an `middleware`. Stellt zusätzlich `/healthz` bereit.

***

### `opa` (Open Policy Agent)

Policy-Engine, geladen mit zwei Policy-Paketen:
* `policy.hot` (`hot.rego`) – Allow/Deny-Entscheidung für jede einzelne Transaktion: erlaubtes Netzwerk, Mindest-/Maximalbetrag, Fee-Grenzen, Tages-Cap (`max_daily_sats`) und Pflichtfelder. Der Operator-Pfad (`rail == "manual"`) überspringt die reinen Betrags-/Fee-Checks, unterliegt aber weiterhin dem Daily-Cap und der Struktur-Prüfung.
* `hot.limits` (`limits.rego`) – berechnet aus dem aktuellen Hot-Wallet-Saldo, ob und in welche Richtung ein Refill nötig ist (`hot_to_cold` / `cold_to_hot` / `hold`), inklusive Risiko-Score und empfohlener Bestätigungstiefe

Limits, Schwellenwerte und erlaubte Netzwerke liegen in `services/opa/data/data.json` und werden zur Laufzeit per `--watch` neu geladen.

***

### `btc-core`

Eigener, aus dem Quellcode gebauter `bitcoind` (Tag `v31.0`), für die lokale Regtest-Umgebung. Kein vorgefertigtes Docker-Image, sondern Multi-Stage-Build direkt aus dem offiziellen Bitcoin-Core-Repository. Verwaltet die Wallets `keyA` (Hot) und `cold-multi` (Cold, watch-only) sowie die Test-Wallets `wallet1`–`wallet3` zur Simulation von Zahlungsverkehr.

Der RPC-Zugriff erfolgt über `rpcauth` mit dynamisch erzeugten, gehashten Zugangsdaten (Salt + HMAC in der gemounteten `rpcauth.conf`). Es existieren zwei getrennte Identitäten für `middleware` und `tx-builder`, `rpcallowip` ist auf das Docker-Subnetz eingeengt, und die lokale CLI arbeitet cookie-basiert – es liegt kein Klartext-Passwort am Server.

***

### `postgres`

Persistiert vier Bereiche (`services/postgres/001_psbt.sql`):
* `btc.wallet` – registrierte Wallets inkl. xpub/Descriptor/Fingerprint
* `btc.psbt` – Zustandsverlauf jeder PSBT über den gesamten Lebenszyklus
* `btc.opa_decision` – jede Policy-Entscheidung inklusive Input/Output, vollständig nachvollziehbar
* `btc.psbt_archive` – abgeschlossene, broadcastete Transaktionen mit Rohdaten, TXID und Hash

Die Middleware verbindet mit einer eingeschränkten Datenbank-Rolle (`mw_app`, nur `SELECT`/`INSERT`/`UPDATE` auf `btc.*`), nicht als Superuser.

***

### `nats`

Event-Bus zwischen `middleware` und `tx-builder`. Relevante Subjects:
* `intent.created` – neue Zahlungsabsicht
* `psbt.build.requested` – Auftrag an `tx-builder`
* `psbt.created` / `psbt.failed` – Ergebnis von `tx-builder` zurück an `middleware`
* `wallet.import.requested` / `wallet.import.done` / `wallet.import.failed` – Wallet-Registrierung

Jeder Teilnehmer besitzt eine eigene, passwortbasierte Identität mit expliziten Publish-/Subscribe-Allowlists (`services/nats/nats-server.conf`): `middleware`, `txbuilder`, `operator` und `setup`. Der NATS-Server veröffentlicht keinen nach außen gerichteten Port.

| Identität | Publish | Subscribe |
|***|***|***|
| `middleware` | `intent.created`, `psbt.build.requested`, `psbt.created`, `wallet.import.done`, `wallet.import.failed` | `intent.created`, `psbt.created`, `psbt.failed`, `wallet.import.requested` |
| `txbuilder` | `psbt.created`, `psbt.failed` | `psbt.build.requested` |
| `operator` | `intent.created` | – |
| `setup` | `wallet.import.requested` | `wallet.import.done`, `wallet.import.failed` |

***

### `ntfy`

Benachrichtigungskanal für den Operator. Gemeldet werden der Cold-Refill-Alarm sowie Fehlerzustände (OPA-Reject, Whitelist-Reject, Signing-/Finalize-/Broadcast-Failed). Aktiv, sobald `NTFY_URL` (und optional `NTFY_TOKEN`) im middleware-Environment gesetzt sind.

***

### Signer-VM (air-gapped, nicht Teil dieses Repos)

Hält den Hot-Signing-Key (Key A). Erreichbar ausschließlich über:
* einen WireGuard-Tunnel (`10.10.0.1` Hot-System ↔ `10.10.0.2` Signer-VM)
* HMAC-signierte Requests (SHA-256, mit Timestamp + Nonce gegen Replay)

Auf der Signer-VM ist das Schlüsselmaterial über das TPM (PCR-versiegelt) gesichert und wird nur bei unverändertem Boot-/Konfigurationszustand entsiegelt. Zusätzlich greift ein harter, vom Basissystem unabhängiger **Velocity-Cap** (Redis), der den Nicht-Change-Abfluss über Single-Sig-Inputs in einem rollierenden Fenster begrenzt (HTTP 429 bei Überschreitung). Die Einrichtung des Tunnels und der Austausch des HMAC-Secrets erfolgt einmalig über das USB-Wechselmedium (siehe unten).

***

## Transaktions-Rails

Die Middleware unterscheidet mehrere „Rails", über die eine Hot-Transaktion angestoßen wird:

| Rail | Auslöser | Whitelist | OPA-Betrags-/Fee-Check | Daily-Cap |
|***|***|***|***|***|
| `bip21` | `POST /api/v1/request/bip21` | ext-Whitelist | ja | ja |
| `psbt` | `POST /api/v1/request/psbt` | ext-Whitelist | ja | ja |
| `manual` | `POST /api/v1/request/psbt` mit gültigem `X-Operator-Token` | Bypass | übersprungen | ja |
| `OPA_hot` / `OPA_cold` | interne Refill-/Sicherungs-Logik | interne Wallets | übersprungen (systemgewählt) | – |

Der **Operator-Pfad** (`manual`) erlaubt es, eine eigene Hot-Transaktion auszulösen – entweder als „Betrag + Adresse" (Intent über die NATS-`operator`-Identität) oder als fertige PSBT über `POST /api/v1/request/psbt`. Der Header `X-Operator-Token` schaltet dabei den Whitelist-Bypass frei; die OPA-Strukturprüfung und der Daily-Cap bleiben aktiv. Das Skript `scripts/ops/psbt_submit.sh` reicht eine mit Sparrow (Watch-Only-Wallet) erstellte PSBT aus einem Verzeichnis über diesen Weg ein.

***

## Sicherheit & Härtung

***

### Container-Härtung (Compose)

* Read-only Rootfs + `tmpfs` für flüchtige Schreibpfade
* `cap_drop: ALL` (Postgres mit minimalem `cap_add`)
* `no-new-privileges`, non-root (uid 1000) für `middleware`/`tx-builder`
* Ressourcenlimits (`mem_limit`, `pids_limit`)
* Keine veröffentlichten Ports außer `middleware` – `postgres`, `opa`, `nats` und `btc-core` sind nur intern erreichbar

***

### Geheimnis-Verwaltung

`scripts/ops/setup/gen_secrets.sh` erzeugt alle Geheimnisse zur Laufzeit und hält sie außerhalb der Versionskontrolle:
* NATS-Passwörter (`middleware`/`txbuilder`/`operator`/`setup`)
* Operator-Token, ntfy-Token
* Postgres-Superuser + eingeschränkte App-Rolle
* btc-core-RPC-Credentials (`rpcauth`, Salt + HMAC)

Die Ausgabe landet in `.env` und `services/btc-core/src/rpcauth.conf` (jeweils `chmod 600`); zusätzlich wird die Verzeichnis-Ownership für die non-root-Container gesetzt. Diese Dateien gehören **nicht** ins Repository – die entsprechenden Pfade müssen in `.gitignore` stehen:

```
.env
services/btc-core/src/rpcauth.conf
middleware_data/
```

***

### Zwei-Schichten-Velocity-Limit

Der Tages-Abfluss ist doppelt begrenzt:
* **OPA-Daily-Cap** (`max_daily_sats`): Das Basissystem zählt den Tages-Abfluss der Zahlungen (nicht der internen Swaps), übergibt `spent_today` in den OPA-Input und blockt mit Deny-Reason `daily limit exceeded`.
* **Signer-Velocity-Cap** (Redis, harter Backstop): Der Signer zählt den Nicht-Change-Abfluss bei Single-Sig-Inputs im rollierenden Fenster und blockt ab dem Cap (HTTP 429). Er ist bewusst höher als der Basis-Cap gewählt und überlebt eine Kompromittierung des Basissystems (konfigurierbar über `VELOCITY_CAP_SATS` / `VELOCITY_WINDOW_SEC` auf der Signer-VM).

***

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
    ntfy/                    # Notification-Schnittstelle
    shared/                  # gemeinsame Health-Check-Helfer

  scripts/
    ops/
      setup/                 # WireGuard-, Wallet- und Secret-Setup (einmalig)
      refill/                # USB-Export/Broadcast für den Cold-Refill-Workflow
      psbt_submit.sh         # manuelle PSBT-Einreichung (Operator-Pfad)
    testing/                  # Regtest-Geldsimulation, HTTP-Testpayloads
```

***

## Setup

***

### Voraussetzungen

* Docker und Docker Compose
* `jq`, `curl` auf allen Hosts, die mit dem USB-Wechselmedium arbeiten
* WireGuard-Tools (`wg`, `wg-quick`) auf Hot-System und Signer-VM
* `openssl` für die Secret-Erzeugung
* Ein dediziertes USB-Wechselmedium mit Label `USB`

***

### 1. Geheimnisse erzeugen (einmalig)

```bash
sudo bash scripts/ops/setup/gen_secrets.sh
```

Erzeugt `.env` und `services/btc-core/src/rpcauth.conf` mit zufälligen Zugangsdaten und setzt die Verzeichnisrechte für die non-root-Container. Ein erneuter Aufruf lässt bestehende Geheimnisse unverändert.

***

### 2. Stack starten

```bash
docker compose up -d
```

Dies startet `postgres` (inkl. Schema-Migration), `nats`, `opa`, `btc-core`, `tx-builder` und `middleware`.

***

### 3. Bitcoin-Core-Wallets initialisieren (einmalig, regtest)

```bash
bash services/btc-core/wallets/wallet_init_oneTime.sh
```

Erzeugt `wallet1`–`wallet3` und exportiert deren Descriptoren nach `services/btc-core/wallets/*.descriptors.json`, damit bei jedem Neustart dieselben Adressen verwendet werden.

***

### 4. WireGuard-Tunnel zur Signer-VM einrichten

Auf dem Hot-System:
```bash
sudo scripts/ops/setup/wg_setup.sh
sudo scripts/ops/setup/wgPeer_export.sh
```

`wg_setup.sh` installiert WireGuard auf dem Host und richtet das `wg0`-Interface (`10.10.0.1`) ein. `wgPeer_export.sh` schreibt den öffentlichen Schlüssel des Hot-Systems auf das eingelegte USB-Medium (`communication/wireguard/wireguard.wallet.json`).
Auf der Signer-VM wird dieselbe JSON-Datei eingelesen und der Peer dort eingetragen (Gegenstück, nicht Teil dieses Repos).
Anschließend, sobald die Signer-VM ihrerseits `wireguard.signer.json` sowie das HMAC-Secret auf dem Medium hinterlegt hat:
```bash
sudo scripts/ops/setup/wgHMAC_import.sh
```

Dies aktiviert den WireGuard-Peer auf dem Hot-System und legt das HMAC-Secret unter `middleware_data/secrets/` ab.

***

### 5. Hot-/Cold-Wallets in der Middleware registrieren

```bash
sudo bash scripts/ops/setup/wallet_import.sh
```

Liest die Hot-/Cold-Wallet-Metadaten vom USB-Medium (`/wallet/hot/…`, `/wallet/cold/cold-signer.wsh`), legt sie unter `middleware_data/wallets/` ab und stößt die Registrierung über NATS (`wallet.import.requested`, Identität `setup`) an. Die Middleware trägt die Wallets daraufhin in Bitcoin Core und PostgreSQL ein.

***

### 6. Externe Partner-Wallets whitelisten

Aus dem Verzeichnis mit den Partner-Metadaten (`*.meta.json`):
```bash
sudo bash scripts/ops/setup/whiteWallet.sh
```

Baut je Partner ein `ext`-Wallet-Payload und stößt den Import ebenfalls über NATS (`wallet.import.requested`) an. Die so registrierten `ext`-Wallets bilden die Whitelist, gegen die dynamisch generierte Zieladressen der `bip21`/`psbt`-Rails geprüft werden.

***

## Transaktionsprozess

***

### Hot-Flow (automatisiert)

1. Externe Anfrage trifft via `POST /api/v1/request/bip21` oder `/psbt` auf `middleware` ein (mit `X-Operator-Token` → Operator-Pfad `manual`).
2. `middleware` veröffentlicht `intent.created`, `tx-builder` baut daraus die PSBT (`psbt.created`). Eine fertige PSBT (`/psbt`) überspringt den Bau und geht direkt in die Prüfung.
3. `middleware` fragt `opa` (`policy.hot`) nach Freigabe (inkl. Daily-Cap).
4. Bei Freigabe wird die Zieladresse gegen die registrierten Wallets geprüft (`whitelist_check`); der Operator-Pfad umgeht diese Prüfung.
5. Die PSBT wird HMAC-signiert an die Signer-VM übergeben und dort – nach Struktur- und Velocity-Prüfung – signiert zurückgegeben.
6. `middleware` finalisiert die PSBT über `btc-core` (`finalizepsbt`) und broadcastet (`sendrawtransaction`). Ein bereits bekannter Broadcast (Mempool/Block) wird idempotent als Erfolg gewertet.
7. Nach erfolgreichem Broadcast wird der aktuelle Hot-Wallet-Saldo erneut gegen `hot.limits` geprüft; bei Bedarf wird automatisch ein Refill-/Sicherungs-Intent erzeugt.

### Cold-Refill-Flow (air-gapped, manuell)

1. `opa` (`hot.limits`) erkennt Unterdeckung der Hot-Wallet und gibt `cold_to_hot` mit empfohlenem Betrag zurück.
2. `tx-builder` erstellt die Refill-PSBT; `middleware` legt sie als `WAITING_HUMAN` ab und sendet einen ntfy-Alarm.
3. Operator exportiert die PSBT auf das USB-Medium:
   ```bash
   sudo API_BASE="http://localhost:8080" scripts/ops/refill/psbt_export.sh
   ```

   Das Skript verweigert den Export, falls bereits eine unbestätigte PSBT (`unappr.*.psbt`) auf dem Medium liegt (Single-Transaction-Regel).
4. Der weitere Ablauf folgt dem bestehenden Air-gapped-PSBT-Runbook: Import in Sparrow auf Key B (und optional Key C), manuelle Prüfung von Zieladresse, Betrag und Gebühr, Signatur, Export als `appr.<psbt_id>.psbt`.
5. Operator liest die signierte PSBT zurück ein:
   ```bash
   sudo API_BASE="http://localhost:8080" scripts/ops/refill/psbt_broadcast.sh
   ```

   `middleware` gleicht die signierte PSBT gegen den DB-Eintrag ab (Betrag/Zieladresse), finalisiert, broadcastet die Transaktion und archiviert sie in `btc.psbt_archive`.

***

## PSBT-Zustände

Jede Statusveränderung wird in `btc.psbt` protokolliert und bildet das Runbook einer Transaktion:

| Status | Beschreibung |
|***|***|
| `INTENT_CREATED` | Eingang der Anfrage an der API-Schnittstelle |
| `PSBT_CREATED` / `PSBT_FAILED` | Nach Erstellung durch den `tx-builder` über Bitcoin Core |
| `OPA_APPROVED` / `OPA_REJECTED` | Nach der Entscheidung durch OPA (Hot-Wallet) |
| `SIGNED` / `SIGNING_FAILED` | Nach Signierung auf der Key-A-VM |
| `FINALIZED` / `FINALIZE_FAILED` | Nach Finalisierung der Hot-PSBT über Bitcoin Core |
| `BROADCASTED` / `BROADCAST_FAILED` | Nach dem Broadcast der Transaktion |
| `WAITING_HUMAN` | Nach Teilsignierung (1/3); warten auf manuelle Cold-Freigabe |
| `COLD_STARTED` | Refill-PSBT auf das Wechselmedium exportiert |
| `COLD_STOPPED` | Veraltete Refill-PSBT gestoppt bzw. gelöscht |

***

## Policies (OPA)

| Policy | Datei | Zweck |
|***|***|***|
| `policy.hot` | `services/opa/policies/hot.rego` | Allow/Deny pro Transaktion (Netzwerk, Betrag, Fee-Grenzen, Daily-Cap, Pflichtfelder) |
| `hot.limits` | `services/opa/policies/limits.rego` | Refill-Logik anhand des aktuellen Hot-Wallet-Saldos inkl. Risk-Score |
| Daten | `services/opa/data/data.json` | Schwellenwerte, Limits, erlaubte Netzwerke |

Die wichtigsten Werte in `data.json`:
* `max_amount_sats`: 5 000 000 (0,05 BTC) pro Transaktion
* `max_daily_sats`: 30 000 000 (0,3 BTC) Tages-Abfluss der Zahlungen
* `max_fee_sats`: 20 000; `min_fee_rate_sat_vb`–`max_fee_rate_sat_vb`: 20–100
* `balance.min` / `balance.max`: 0,5 / 2,0 BTC (Refill-Schwellen)
* erlaubte Netzwerke: nur `regtest`

Aus dem Saldo bestimmt `hot.limits` einen Risk-Score, der Bestätigungstiefe und Gebühren-Modus der Austausch-Transaktion festlegt:

| Risk-Score | ≤ 30 | 30 < x ≤ 70 | > 70 |
|***|***|***|***|
| Confirmation Blocks | 6 | 3 | 1 |
| Estimate Mode | economical | conservative | conservative |

Änderungen an `data.json` oder den `.rego`-Dateien werden vom laufenden OPA-Container automatisch übernommen (`--watch`).

***

## Monitoring & Benachrichtigungen

* `/metrics` (Prometheus) auf der `middleware` mit zentralen Lifecycle-Countern (Intents, PSBT-Bau, OPA-Entscheidungen, Whitelist-/Velocity-Blocks, Refill-Aktionen, Signier-/Broadcast-Ergebnisse, Hot-Balance, wartende Cold-PSBTs)
* Strukturierte JSON-Logs für den Loki-Ingest
* ntfy-Push für Cold-Refill-Alarm und Fehlerzustände

Der Betrieb von Prometheus/Loki/ntfy-Servern selbst ist Teil des Infrastruktur-Scopes und nicht dieses Stacks.

***

## Testing / Lokale Simulation

Der Ordner `scripts/testing/` enthält ein Set für die Regtest-Umgebung. Ein vollständiger Durchlauf sieht so aus:

***

### 1. Wallets laden und initial befüllen

```bash
bash scripts/testing/btc-core/load_wallets.sh
```

Lädt `wallet1`/`wallet3`, mined 101 Blöcke auf `wallet1` (Coinbase-Reife) und verteilt Startguthaben auf `wallet2`/`wallet3`.

***

### 2. Hot-Wallet-Saldo in einen Grenzbereich bringen

Über-Deckung simulieren (Hot > Maximum → löst automatisch `hot_to_cold` aus):
```bash
bash scripts/testing/btc-core/simMoney_save.sh
```

Unter-Deckung simulieren (Hot < Minimum → löst den Cold-Refill-Prozess `cold_to_hot` aus):
```bash
bash scripts/testing/btc-core/simMoney_refill.sh
```

Beide Skripte senden Guthaben an `keyA` (Hot) bzw. `cold-multi` (Cold) und minen einen Bestätigungsblock. Die Balance-Prüfung wird nach der nächsten Hot-Transaktion ausgelöst.

***

### 3. Hot-Flow über die HTTP-API anstoßen

```bash
python3 scripts/testing/send_intent_API.py
```

Erzeugt eine frische Zieladresse auf `wallet2`, stößt darüber den `BIP21`-Flow (`/bip21`) an und baut anschließend eine fertige PSBT aus `keyA`, die über `/psbt` eingereicht wird. Damit die Whitelist-Prüfung greift, muss `wallet2` zuvor als `ext`-Wallet registriert sein (siehe „Externe Partner-Wallets whitelisten").

***

### 4. Manuelle Operator-Transaktion einreichen

```bash
sudo API_BASE="http://localhost:8080" scripts/ops/psbt_submit.sh /pfad/zum/sparrow-export
```

Sucht genau eine `*.psbt` (Single-TX-Regel) im angegebenen Verzeichnis, erkennt Binär- vs. Base64-Format, berechnet den SHA-256 über die dekodierten Bytes und reicht die PSBT mit `X-Operator-Token` über `/psbt` ein (Rail `manual`, Whitelist-Bypass).

***

### 5. Cold-Refill vollständig durchspielen

Nach `simMoney_refill.sh` und einer auslösenden Hot-Transaktion liegt eine `WAITING_HUMAN`-PSBT bereit. Diese über den USB-Workflow exportieren, in Sparrow mit Key B (und optional Key C) signieren und zurück einlesen:
```bash
sudo API_BASE="http://localhost:8080" scripts/ops/refill/psbt_export.sh
# … Signatur in Sparrow, Export als appr.<psbt_id>.psbt …
sudo API_BASE="http://localhost:8080" scripts/ops/refill/psbt_broadcast.sh
```

***