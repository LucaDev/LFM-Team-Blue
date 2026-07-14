# Bitcoin Simulation

## Leitplanken

- Auf `ailab2` sind nur Dummy-Deskriptoren, Dummy-PSBTs, Dummy-Receipts und Platzhalter-Konfigurationen erlaubt.
- Verboten bleiben echte Seeds, echte `xprv`, echte `wallet.dat`, produktive Private Keys und produktive API-Schluessel.
- Es werden keine echten Bitcoin-Daemons, kein Chain-Sync, kein Electrs, kein HWI und keine Onion-Veröffentlichungen fuer Bitcoin-Dienste ausgerollt.
- Der simulierte Offline-Handoff liegt root-only unter `/root/ailab-runtime/bitcoin-sim-offline` und bleibt bewusst ausserhalb von `outputs` und ausserhalb des IaC-Pfads.

## Rollenmodell

### `203 vm-bitcoin-node`

- Rolle: Watch-only-/Referenzkontext
- Datenklasse:
  - erlaubt: Dummy-Deskriptor, Dummy-UTXO-Referenz, Dummy-Fee-Policy, Watch-only-Bundle
  - verboten: unsigned PSBTs, signed PSBTs, Broadcast-Receipts, reale Signing-Artefakte
- Dateipfade:
  - `/srv/bitcoin-sim/node/reference`
  - `/srv/bitcoin-sim/node/export`
  - `/srv/bitcoin-sim/node/validation`

### `204 vm-bitcoin-service`

- Rolle: Hot-Service-Simulation ohne echte Wallet
- Datenklasse:
  - erlaubt: Dummy-Payout-Requests, Watch-only-Bundle, unsigned Dummy-PSBT, signed Dummy-Import, Dummy-Broadcast-Receipt
  - verboten: Seeds, `xprv`, `wallet.dat`, produktive Wallet-Dateien, reale Signaturschluessel
- Dedizierter Account:
  - `btcpayout`
  - kein Login-Shell-Zweck, nur Dateiverarbeitung im Simulationspfad
- Dateipfade:
  - `/srv/bitcoin-sim/service/inbox/requests`
  - `/srv/bitcoin-sim/service/reference`
  - `/srv/bitcoin-sim/service/work/unsigned-psbt`
  - `/srv/bitcoin-sim/service/import/signed`
  - `/srv/bitcoin-sim/service/outbox/receipts`
  - `/srv/bitcoin-sim/service/archive`
  - `/srv/bitcoin-sim/service/validation`

### Simulierter Offline-Signer

- Kein eigener Gast auf `ailab2`
- Rein organisatorisch simuliert ueber den root-only Hostpfad:
  - `/root/ailab-runtime/bitcoin-sim-offline/watchonly-export`
  - `/root/ailab-runtime/bitcoin-sim-offline/unsigned`
  - `/root/ailab-runtime/bitcoin-sim-offline/signed`
  - `/root/ailab-runtime/bitcoin-sim-offline/receipts`
- Keine echten Seeds, keine echten Schluessel, nur klar markierte Dummy-Artefakte

## Umgesetzt 2026-07-08

- `203` und `204` wurden in Abschnitt 06 offline auf dem Host vorbereitet und nur fuer kurze Validator-Boots gestartet.
- `203` erzeugt jetzt ein Dummy-Watch-only-Bundle mit:
  - Descriptor-Template
  - Dummy-UTXO-Referenz
  - Dummy-Fee-Policy
- `204` verarbeitet jetzt einen dateibasierten Dummy-Payout-Workflow mit zwei Phasen:
  - Phase 1: Request plus Watch-only-Bundle erzeugen einen unsigned Dummy-PSBT
  - Phase 2: simuliertes signed Dummy-Artefakt fuehrt zu einem Dummy-Broadcast-Receipt
- Fuer beide VMs wurde `/boot/efi` in `/etc/fstab` mit `nofail,x-systemd.device-timeout=1s` gehaertet, damit die TCG-/EFI-Testbasis nicht vorzeitig in einen defekten Bootpfad kippt.
- Nach erfolgreicher Validierung wurden die Snapshots `post-bitcoin-sim` fuer `203` und `204` angelegt.

## Dummy-PSBT-Ablauf

1. `203` schreibt `watchonly-bundle.json` als reines Referenzartefakt.
2. Der Host kopiert dieses Bundle root-only in den Offline-Handoff und danach nach `204`.
3. `204` Phase 1 erzeugt `payout-0001-unsigned.psbt.json`.
4. Der Host schreibt root-only `payout-0001-signed.psbt.json` als klar markierten Offline-Dummy.
5. `204` Phase 2 importiert dieses Dummy-Artefakt und erzeugt `payout-0001-broadcast.json`.

## Validierter Zustand

- Keine Bitcoin-Listener offen:
  - `203` und `204` melden fuer `8332`, `8333`, `18332`, `18333`, `18443`, `18444`, `50001`, `50002`, `50011`, `50012`, `3000` und `3002` jeweils `absent`
- Keine Bitcoin-Daemons aktiv:
  - `bitcoin_daemons=absent` auf `203` sowie in Phase 1 und Phase 2 auf `204`
- Verbotene Artefakte fehlen:
  - `wallet_dat=absent`
  - `seed_files=absent`
  - `xprv_files=absent`
- Rechte sind eng gesetzt:
  - `203` Referenz- und Exportpfade `750 root:root`, Bundle-Dateien `640 root:root`
  - `204` Servicepfade mit `root:btcpayout`, Schreibpfade `770`, Import-/Referenzpfade `750`, Archiv `700 root:root`
  - Offline-Handoff-Dateien auf dem Host `600 root:root`
- Workflow ist Ende-zu-Ende nachgewiesen:
  - Phase 1: `request_present=yes`, `reference_present=yes`, `unsigned_present=yes`, `signed_present=no`, `receipt_present=no`
  - Phase 2: `request_present=yes`, `reference_present=yes`, `unsigned_present=yes`, `signed_present=yes`, `receipt_present=yes`

## Grenzen der Simulation

- Keine echte Interoperabilitaet mit Bitcoin Core, HWI, Electrs oder produktiven Wallets nachgewiesen
- Keine echte Signaturpruefung und kein echter Broadcast
- Kein produktiver Backup-/Retention-Pfad fuer den root-only Offline-Handoff
