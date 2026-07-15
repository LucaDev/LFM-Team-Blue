# Hot-Wallet – Ops- & Testing-Skripte

Dieses Verzeichnis enthält die Hilfsskripte rund um den Hot-Wallet-Stack (Service-Stack siehe [`services/hotwallet/`](../../services/hotwallet/README.md)). Sie sind aus dem eigenständigen `Hot-Wallet`-Repo übernommen und auf die apphost-Pfade angepasst.

Gemeinsame Konventionen fast aller Skripte:

- **`PROJECT_ROOT`** wird relativ zum Skript aufgelöst und zeigt auf das apphost-Repo-Root.
- **`.env`** im Repo-Root wird geladen; benötigt werden je nach Rolle die NATS-Passwörter (`HOTWALLET_NATS_OPERATOR_PASS`, `HOTWALLET_NATS_SETUP_PASS`).
- **`docker-compose.yml`** und ein **laufender Stack** sind Voraussetzung – die Skripte publizieren nur NATS-Events via `hotwallet-middleware`; die eigentliche Arbeit erledigt der Stack.
- Staging-/Laufzeitdateien liegen unter **`secrets/hotwallet/`** (gitignored). Dieses Verzeichnis ist in die Container gemountet, dort als `/run/` sichtbar.

***

## `ops/` – Betriebspfade

### `psbt_submit.sh` — manueller Operator-Pfad

Reicht eine fertige, extern erzeugte PSBT als Operator ein und publiziert `psbt.submit.requested` (Rail `manual`: Whitelist-Bypass, OPA überspringt Betrags-/Fee-Checks, Daily-Cap + Velocity-Cap bleiben aktiv).

| | |
|---|---|
| **Aufruf** | `./ops/psbt_submit.sh [PSBT_DIR]` (Default: Env `PSBT_DIR` oder das Skriptverzeichnis) |
| **Input** | genau **eine** `*.psbt` im `PSBT_DIR` (Binär-PSBT mit Magic `70736274ff` oder Base64-Text) |
| **Braucht** | `.env` (`HOTWALLET_NATS_OPERATOR_PASS`), `docker-compose.yml`, laufender Stack; `jq`, `base64`, `sha256sum` |
| **Schreibt** | `secrets/hotwallet/ops_submit.json` (Payload `{psbt, sha256}` → im Container `/run/ops_submit.json`) |
| **Event** | `psbt.submit.requested` (Identität `operator`) |

### `ops/refill/psbt_export.sh` — Cold-Refill: PSBT exportieren

Kopiert die von der Middleware gestagte Refill-PSBT in das Transfer-Verzeichnis, von wo sie per SSH abgeholt und über USB an die air-gapped Cold-VM (Sparrow) übergeben wird. Meldet `refill.export.done`.

| | |
|---|---|
| **Aufruf** | `sudo ./ops/refill/psbt_export.sh` (**root** erforderlich) |
| **Input** | `secrets/hotwallet/refill.psbt` **und** `secrets/hotwallet/refill.psbt.id` (beide von der Middleware gestaged) |
| **Braucht** | `.env`, `docker-compose.yml`, laufender Stack; `jq` |
| **Schreibt** | `${TRANSFER_DIR:-secrets/hotwallet/transfer}/psbt/<psbt_id>.psbt` (Verzeichnis muss leer sein – Single-TX), `secrets/hotwallet/ops_export_done.json` |
| **Event** | `refill.export.done` |

### `ops/refill/psbt_broadcast.sh` — Cold-Refill: signierte TX broadcasten

Gegenstück zum Export: liest die aus dem Cold-Workflow zurückkopierte, signierte Roh-Transaktion ein und publiziert `refill.broadcast.requested`.

| | |
|---|---|
| **Aufruf** | `sudo ./ops/refill/psbt_broadcast.sh` (**root** erforderlich) |
| **Input** | genau **eine** `<psbt_id>.txn` (Hex-Rohtransaktion) in `${TRANSFER_DIR:-secrets/hotwallet/transfer}/psbt/`, zuvor per SSH dorthin kopiert |
| **Braucht** | `.env`, `docker-compose.yml`, laufender Stack; `jq` |
| **Schreibt** | `secrets/hotwallet/ops_broadcast.json` (Payload `{psbt_id, tx}`) |
| **Event** | `refill.broadcast.requested` |

***

## `ops/setup/` – Einrichtung

### `wallet_import.sh` — Hot-/Cold-Signer importieren

Importiert die interne Hot-Wallet und den Cold-Signer und stößt pro Typ `wallet.import.requested` an. Erwartet die zuvor per SSH auf den Apphost kopierten Wallet-Dateien im **aktuellen Arbeitsverzeichnis** (`TRANSFER_DIR="./"`).

| | |
|---|---|
| **Aufruf** | `./wallet_import.sh` aus dem Verzeichnis, das den `wallet/`-Ordner enthält |
| **Input** | `./wallet/hot/` mit `metadata.json` + `xpub.txt`; `./wallet/cold/` mit `cold-signer.wsh` (letzte Zeile = Descriptor) |
| **Braucht** | `.env` (`HOTWALLET_NATS_SETUP_PASS`), `docker-compose.yml`, laufender Stack; `jq` |
| **Schreibt** | kopiert nach `secrets/hotwallet/wallets/<hot\|cold>/`, patcht/erzeugt jeweils `metadata.json` |
| **Event** | `wallet.import.requested` (Identität `setup`), je Wallet-Typ |

### `whiteWallet.sh` — externe Whitelist-Wallets registrieren

Liest eine oder mehrere `*.meta.json` ein und registriert daraus `ext`-Wallets (Empfänger-Whitelist für den `psbt`-Rail).

| | |
|---|---|
| **Aufruf** | `./whiteWallet.sh [SRC_DIR]` (Default `.`) |
| **Input** | `*.meta.json` mit `wallet_name`, `network`, optional `xpub`/`descriptor`/`derivation_path`/`master_fingerprint` – Vorlage: [`wallet2.meta.json`](ops/setup/wallet2.meta.json) |
| **Braucht** | `.env` (`HOTWALLET_NATS_SETUP_PASS`), `docker-compose.yml`, laufender Stack; `jq` |
| **Schreibt** | `secrets/hotwallet/wallets/ext/<wallet_name>.json` |
| **Event** | `wallet.import.requested` (Typ `ext`), je Datei |

### `wgPeer_export.sh` — WireGuard-Peer-Daten ausgeben

Gibt die WireGuard-Peer-Konfiguration der Hot/Wallet-Seite als JSON auf **stdout** aus (Public Key, IPs, Port, Endpoint), zur Übergabe an die Signer-VM. Publiziert nichts und braucht keinen Stack.

| | |
|---|---|
| **Aufruf** | `[SIGNER_ENDPOINT_IP=<ip>] ./wgPeer_export.sh` (Endpoint-IP wird sonst aus der Default-Route ermittelt) |
| **Braucht** | `/var/lib/wireguard/private.key`, `wg` (wireguard-tools) |
| **Ausgabe** | JSON auf stdout (Tunnel `10.10.0.1` Wallet ↔ `10.10.0.2` Signer, Port `51820`) |

### `wallet2.meta.json`

Beispiel-Metadaten (keine ausführbare Datei) als Eingabe für `whiteWallet.sh`.

***

## `testing/` – Test & Regtest-Simulation

> Nur für die lokale **Regtest**-Umgebung gedacht. Alle Skripte sprechen den Container `hotwallet-btc-core` bzw. die Middleware-API an.

### `send_intent_API.sh` / `send_intent_API.py`

Testclient, der einen BIP21- und einen PSBT-Request gegen die Middleware-API absetzt. Beide Varianten sind funktional gleich: die `.sh` nutzt `curl`+`jq`, die `.py` nutzt `requests`. Adressen und die zu sendende PSBT werden über `bitcoin-cli` im `hotwallet-btc-core`-Container erzeugt (`getnewaddress`, `walletcreatefundedpsbt`).

| | |
|---|---|
| **Aufruf** | `./testing/send_intent_API.sh` bzw. `python3 testing/send_intent_API.py` |
| **Braucht** | laufender Stack, erreichbare API (`BASE` im Skript anpassen – `.sh`: `https://hotwallet.<domain>/…`, `.py`: `http://localhost:8080/…`); geladene Wallets `wallet2` (Ziel) und `keyA` (Quelle); Container `hotwallet-btc-core`; `.sh`: `curl`, `jq`; `.py`: `requests` |
| **Tut** | `POST /api/v1/request/bip21` und `POST /api/v1/request/psbt` |

### `testing/btc-core/load_wallets.sh`

Einmaliges Aufsetzen der Regtest-Nodes: erstellt `wallet1`/`wallet3`, mined 101 Startblöcke und verteilt Guthaben, damit über mehrere Läufe dieselben Adressen entstehen (wichtig für das OPA-Whitelisting).

| | |
|---|---|
| **Aufruf** | `./testing/btc-core/load_wallets.sh` |
| **Braucht** | laufender Container `hotwallet-btc-core` (Regtest); wartet selbst auf die RPC-Verfügbarkeit |

### `testing/btc-core/simMoney_refill.sh` / `simMoney_save.sh`

Simulieren Geldflüsse in die Hot-Wallet (`keyA`) und Cold-Wallet (`cold-multi`), um die Refill-Logik zu triggern: `simMoney_refill.sh` erzeugt eine Unterdeckung, `simMoney_save.sh` eine Überdeckung. Anschließend wird ein Block gemined (Bestätigung).

| | |
|---|---|
| **Aufruf** | `./testing/btc-core/simMoney_refill.sh` bzw. `simMoney_save.sh` |
| **Braucht** | laufender Container `hotwallet-btc-core`; geladene/importierte Wallets `wallet1` (Funding-Quelle), `keyA`, `cold-multi` |

***

## Typische Reihenfolge

1. **Einmalig:** `testing/btc-core/load_wallets.sh` → `ops/setup/wallet_import.sh` → `ops/setup/whiteWallet.sh`; WireGuard/Signer-VM über `wgPeer_export.sh` (+ Signer-seitige Skripte).
2. **Test:** `testing/send_intent_API.sh`, bei Bedarf `simMoney_refill.sh`/`simMoney_save.sh` zum Auslösen des Refill-Pfads.
3. **Manuell/Cold-Refill:** `ops/psbt_submit.sh` (Operator-PSBT) bzw. `ops/refill/psbt_export.sh` → Cold-Signing → `ops/refill/psbt_broadcast.sh`.

Vollständiger Ablauf inkl. Secrets, WireGuard und Cold-Refill: [Abschnitt 17 der Installationsanleitung](../../Installationsanleitung.md#17-hot-wallet-bitcoin-custody-stack).
