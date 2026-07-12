# Hot-Wallet – Automatisierter Hot-Flow & Air-gapped Cold-Refill

***

> [!NOTE]
> Dieser Stack wurde aus dem eigenständigen `Hot-Wallet`-Repository in apphost integriert. Unterschiede zum Original sind unten unter „Integration in apphost" zusammengefasst; siehe auch [Abschnitt 18](../../Installationsanleitung.md#18-hot-wallet-bitcoin-custody-stack) der Installationsanleitung für Setup/Betrieb.

## Ziel

Dieses Verzeichnis enthält den Service-Stack für den `btc-hot`-Teil des Bitcoin-Custody-Setups:

- automatisiertes Signieren und Broadcasten ausgehender Hot-Wallet-Transaktionen, gesteuert über eine Policy-Engine (OPA)
- ein manueller Operator-Pfad, über den eine eigene Hot-Transaktion (Betrag + Adresse oder fertige PSBT) ausgelöst werden kann
- automatische Erkennung von Über-/Unterdeckung der Hot-Wallet und Erzeugung der entsprechenden Refill-Transaktionen
- Übergabe an den air-gapped Cold-Signing-Workflow (Sparrow/Key B/Key C), sobald eine menschliche Freigabe nötig ist

Der Stack ist bewusst in containerisierte Services aufgeteilt und kommuniziert intern über NATS. Die eigentliche Signatur der Hot-Transaktionen erfolgt **nicht** in diesem Stack, sondern auf einer separaten Signer-VM, die ausschließlich über WireGuard + HMAC erreichbar ist.

***

## Integration in apphost

Gegenüber dem eigenständigen Original-Repository wurde Folgendes angepasst:

- **Compose:** Ein Service-Block `compose/finance/hotwallet.yml` statt eigenem `docker-compose.yaml`. Service- und Container-Namen sind mit `hotwallet-` präfixiert (`hotwallet-postgres`, `hotwallet-nats`, `hotwallet-opa`, `hotwallet-btc-core`, `hotwallet-tx-builder`, `hotwallet-middleware`), um Namenskollisionen mit anderen apphost-Diensten auszuschließen.
- **Secrets:** Alle `.env`-Variablen sind mit `HOTWALLET_` präfixiert (z. B. `HOTWALLET_RPC_PASS_MW` statt `BTC_RPC_PASS_MW`, `HOTWALLET_NATS_MW_PASS` statt `MW_NATS_PASS`). `scripts/ops/setup/gen_secrets.sh` und `rotate_secrets.sh` aus dem Original entfallen; stattdessen: Passwörter in der gemeinsamen `.env` setzen und `bash scripts/update-secrets-hotwallet.sh` für die `rpcauth.conf` ausführen (siehe Installationsanleitung).
- **Laufzeit-Daten:** `middleware_data/` (Wallet-Metadaten, Signer-HMAC-Secret, PSBT-Staging) liegt jetzt unter `secrets/hotwallet/` (gitignored), analog zum bestehenden apphost-`secrets/`-Verzeichnis.
- **ntfy:** Der im Original enthaltene eigene `ntfy`-Container (`services/ntfy/`) wird **nicht** genutzt. Benachrichtigungen laufen über den bestehenden apphost-ntfy-Dienst; dafür wurde `services/middleware/src/com/ntfy.py` um Basic-Auth-Unterstützung (`NTFY_USER`/`NTFY_PASSWORD`) erweitert, da der apphost-ntfy-Dienst Benutzer/Passwort statt Access-Token verwendet.
- **Exposition:** `hotwallet-middleware` ist über Traefik unter `https://${HOTWALLET_SUBDOMAIN}.${DOMAIN}` erreichbar, mit eigener Autorisierung (OPA + Whitelist) statt Authelia – siehe Installationsanleitung für die Begründung.
- **Ops-Skripte:** `scripts/ops/*` und `scripts/testing/*` liegen jetzt unter `scripts/hotwallet/`, mit angepassten Pfaden (`PROJECT_ROOT`, `docker-compose.yml` statt `.yaml`, `secrets/hotwallet/` statt `middleware_data/`).
- **WireGuard-Tunnel zur Signer-VM:** Noch **nicht** eingerichtet – nur die benötigten Werkzeuge (`wireguard-tools`, `jq`, `openssl`) sind auf dem NixOS-Host bereits vorhanden. `scripts/hotwallet/ops/setup/wg_setup.sh` funktioniert unverändert, muss aber weiterhin manuell ausgeführt werden.

Alles Folgende beschreibt den unveränderten Rest der Original-Architektur.

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

Zusätzlich existiert der manuelle Cold-Refill-Pfad: Sinkt die Hot-Wallet unter den definierten Schwellenwert, wird eine Refill-PSBT erzeugt und über das dedizierte USB-Wechselmedium an den air-gapped Cold-Workflow (Sparrow, Key B/Key C) übergeben.

***

## Komponenten und Verantwortung

### `middleware` (FastAPI, Port 8080, intern)

Zentrale Orchestrierung: nimmt externe Zahlungsanfragen entgegen (`POST /api/v1/request/bip21`, `POST /api/v1/request/psbt`), fragt OPA für jede zu signierende PSBT um Entscheidung an (Betrags-, Fee- und Daily-Cap-Prüfung), prüft die Zieladresse gegen die registrierten Wallets (Whitelist), leitet zu signierende PSBTs HMAC-authentifiziert an die Signer-VM weiter, finalisiert und broadcastet signierte Transaktionen über `btc-core`, persistiert Zustände/Policy-Entscheidungen/Transaktionen in PostgreSQL, stellt den Cold-Refill-Workflow bereit und `/healthz`, `/health`, `/metrics` (Prometheus).

> Hinweis: Der in der Architektur-Beschreibung erwähnte `X-Operator-Token`-Bypass für den manuellen Pfad ist im aktuellen Code nicht implementiert (siehe „Bekannte Lücken" in der Installationsanleitung) – jede Anfrage durchläuft dieselbe OPA-/Whitelist-Prüfung.

### `tx-builder`

Reagiert auf NATS-Intents (`psbt.build.requested`) und baut daraus über Bitcoin Core (`walletcreatefundedpsbt`) die eigentliche PSBT, inklusive Gebührenschätzung passend zum jeweiligen Risiko-Score der Refill-Entscheidung. Meldet Erfolg (`psbt.created`) oder Fehlschlag (`psbt.failed`) zurück an `middleware`. Stellt `/healthz` bereit.

### `opa` (Open Policy Agent)

Policy-Engine mit zwei Policy-Paketen:
* `policy.hot` (`hot.rego`) – Allow/Deny-Entscheidung pro Transaktion: erlaubtes Netzwerk, Mindest-/Maximalbetrag, Fee-Grenzen, Tages-Cap (`max_daily_sats`), Pflichtfelder.
* `hot.limits` (`limits.rego`) – berechnet aus dem aktuellen Hot-Wallet-Saldo, ob und in welche Richtung ein Refill nötig ist (`hot_to_cold`/`cold_to_hot`/`hold`), inklusive Risiko-Score und empfohlener Bestätigungstiefe.

Limits liegen in `opa/data/data.json` und werden zur Laufzeit per `--watch` neu geladen:
* `max_amount_sats`: 5.000.000 (0,05 BTC) pro Transaktion
* `max_daily_sats`: 30.000.000 (0,3 BTC) Tages-Abfluss
* `max_fee_sats`: 20.000; Fee-Rate 20–100 sat/vB
* `balance.min`/`balance.max`: 0,5/2,0 BTC (Refill-Schwellen)
* erlaubte Netzwerke: nur `regtest`

### `btc-core`

Eigener, aus dem Quellcode gebauter `bitcoind` (Tag `v31.0`), für die lokale Regtest-Umgebung. Verwaltet die Wallets `keyA` (Hot) und `cold-multi` (Cold, watch-only). RPC-Zugriff über `rpcauth` mit dynamisch erzeugten, gehashten Zugangsdaten (`rpcauth.conf`, generiert von `scripts/update-secrets-hotwallet.sh`); zwei getrennte Identitäten für `middleware` und `tx-builder`.

### `postgres`

Persistiert vier Bereiche (`postgres/001_psbt.sql`): `btc.wallet`, `btc.psbt`, `btc.opa_decision`, `btc.psbt_archive`. Die Middleware verbindet mit einer eingeschränkten Rolle (`mw_app`, nur `SELECT`/`INSERT`/`UPDATE` auf `btc.*`), nicht als Superuser.

### `nats`

Event-Bus zwischen `middleware` und `tx-builder`. Jeder Teilnehmer (`middleware`, `txbuilder`, `operator`, `setup`) hat eine eigene, passwortbasierte Identität mit expliziten Publish-/Subscribe-Allowlists (`nats/nats-server.conf`). Kein nach außen gerichteter Port.

### ntfy

Siehe „Integration in apphost" oben – nutzt den bestehenden apphost-ntfy-Dienst, Topic `hotwallet-alerts`, Alarm bei Cold-Refill und Fehlerzuständen (OPA-Reject, Whitelist-Reject, Signing-/Finalize-/Broadcast-Failed).

### Signer-VM (air-gapped, nicht Teil dieses Repos)

Hält den Hot-Signing-Key (Key A). Erreichbar ausschließlich über einen WireGuard-Tunnel (`10.10.0.1` Hot-System ↔ `10.10.0.2` Signer-VM) und HMAC-signierte Requests. Schlüsselmaterial liegt TPM-versiegelt vor, zusätzlich ein Velocity-Cap (Redis) auf der Signer-VM selbst. Einrichtung erfolgt einmalig über das USB-Wechselmedium – siehe `scripts/hotwallet/ops/setup/wg_setup.sh`, `wgPeer_export.sh`, `wgHMAC_import.sh`.

***

## Transaktions-Rails

| Rail | Auslöser | Whitelist | OPA-Betrags-/Fee-Check | Daily-Cap |
|---|---|---|---|---|
| `bip21` | `POST /api/v1/request/bip21` | ext-Whitelist | ja | ja |
| `psbt` | `POST /api/v1/request/psbt` | ext-Whitelist | ja | ja |
| `OPA_hot`/`OPA_cold` | interne Refill-/Sicherungs-Logik | interne Wallets | übersprungen (systemgewählt) | – |

***

## PSBT-Zustände

| Status | Beschreibung |
|---|---|
| `INTENT_CREATED` | Eingang der Anfrage an der API-Schnittstelle |
| `PSBT_CREATED`/`PSBT_FAILED` | Nach Erstellung durch den `tx-builder` |
| `OPA_APPROVED`/`OPA_REJECTED` | Nach der Entscheidung durch OPA |
| `SIGNED`/`SIGNING_FAILED` | Nach Signierung auf der Key-A-VM |
| `FINALIZED`/`FINALIZE_FAILED` | Nach Finalisierung über Bitcoin Core |
| `BROADCASTED`/`BROADCAST_FAILED` | Nach dem Broadcast der Transaktion |
| `WAITING_HUMAN` | Nach Teilsignierung (1/3); wartet auf manuelle Cold-Freigabe |
| `COLD_STARTED`/`COLD_STOPPED` | Refill-PSBT exportiert / veraltete Refill-PSBT gestoppt |

***

## Container-Härtung

* Read-only Rootfs + `tmpfs` für flüchtige Schreibpfade
* `cap_drop: ALL` (Postgres mit minimalem `cap_add`)
* `no-new-privileges`, non-root (uid 1000) für `middleware`/`tx-builder`
* Ressourcenlimits über `deploy.resources.limits`
* Keine veröffentlichten Ports außer `hotwallet-middleware` – alle übrigen Services sind nur über `finance-network` (intern) erreichbar

***

## Setup, Betrieb, Testing

Siehe [Abschnitt 18 der Installationsanleitung](../../Installationsanleitung.md#18-hot-wallet-bitcoin-custody-stack) für die vollständige Schritt-für-Schritt-Anleitung (Secrets, Stack-Start, Wallet-Import, WireGuard, Cold-Refill, Testing).
