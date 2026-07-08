# Bitcoin-Betriebsablauf

## Ziel

Das System trennt alltaegliche Auszahlungen von langfristiger Verwahrung. Der Server uebernimmt nur online benoetigte Aufgaben; langfristige Signierschluessel und Seeds bleiben offline.

## Rollen

- `btc-node`: validiert die Blockchain, baut Transaktionen vor und sendet signierte Transaktionen ins Netzwerk.
- `Treasury`: langfristige Verwahrung auf einem Offline-Geraet oder einer Hardware-Wallet.
- `Hot-Wallet`: kleine Online-Wallet fuer automatische oder haeufige Auszahlungen mit festem Betragslimit.

## Zulaessiges Material auf `btc-node`

- erlaubt: Bitcoin-Core-Konfiguration, Watch-only-Deskriptoren oder `xpub`s der Treasury, kleine Hot-Wallet fuer Betriebszahlungen
- verboten: Cold-Seed, Treasury-Private-Keys, Klartext-Seeds, zentrale Sammeldateien mit Recovery-Material

## Geplanter Ablauf

1. Erzeuge den Treasury-Seed ausschliesslich offline und niemals auf `btc-node`.
2. Importiere auf `btc-node` nur Watch-only-Deskriptoren oder `xpub`s der Treasury, damit Salden und UTXOs sichtbar sind, ohne dass langfristige Private Keys online liegen.
3. Erzeuge fuer automatische Auszahlungen eine separate Hot-Wallet mit engem Guthaben- und Tageslimit.
4. Halte Bitcoin-Core-RPC auf `127.0.0.1` gebunden. Browser oder entfernte Clients signieren niemals direkt ueber RPC.
5. Fuer Treasury-Bewegungen erstellt der Server nur eine PSBT aus den Watch-only-Daten. Die Signatur erfolgt ausschliesslich offline; der Server sendet danach nur die fertige Transaktion.
6. Fuelle die Hot-Wallet nur kontrolliert aus der Treasury nach, idealerweise ueber einen dokumentierten Freigabeprozess mit Betragsschwellen.
7. Sichere Seeds ausschliesslich offline oder in getrennten verschluesselten Recovery-Medien. Sichere Watch-only-Daten, Hot-Wallet-Metadaten, Node-Konfiguration und Onion-Identitaeten getrennt voneinander.
8. Teste Wiederherstellung, PSBT-Fluss, Broadcast und Hot-Wallet-Nachfuellung regelmaessig in einer isolierten Testumgebung, bevor echte Mittel verwendet werden.

## Erwarteter Vorteil

- begrenzter Schaden bei einer Server-Kompromittierung
- klare Trennung zwischen Bequemlichkeit und Verwahrung
- nachvollziehbarer Recovery- und Freigabeprozess
