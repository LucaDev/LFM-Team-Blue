# Bitcoin-Betriebsablauf

## Ziel

Das System soll regelmaessige automatische Auszahlungen mit kleinem Hot-Bestand ermoeglichen, waehrend der langfristige Bestand strikt getrennt in einem Offline-Kontext verwahrt wird.

## Rollen

- Online-Payout-Service:
  - haelt nur einen begrenzten Hot-Wallet-Kontext fuer automatisierte Auszahlungen
  - darf unsigned PSBTs erzeugen, signierte PSBTs importieren und broadcasten
- Watch-only-Node:
  - haelt nur Deskriptoren oder `xpub`-/Watch-only-Daten
  - beobachtet Treasury-UTXOs und bereitet unsigned PSBTs vor
- Offline-Signer:
  - haelt Cold-Seeds und Private Keys
  - signiert Treasury-PSBTs ausschliesslich offline

## Geplanter Ablauf

1. Erzeuge Cold-Seeds und langfristige Treasury-Keys ausschliesslich auf einem separaten Offline-Geraet.
2. Exportiere nur Watch-only-Deskriptoren oder `xpub`-basierte Beobachtungsdaten auf den Online-Node. Seeds, `xprv` und andere Private Keys bleiben offline.
3. Betreibe fuer automatische Auszahlungen einen getrennten Hot-Wallet-Kontext mit festem Bestandslimit und dokumentiertem Refill-Prozess.
4. Halte Bitcoin-Core-RPC ausschliesslich auf internen Interfaces oder einem strikt operator-only-Pfad; keine Browser-Signierung und keine direkte RPC-Veroeffentlichung fuer Endnutzer.
5. Fuer Treasury-Bewegungen erstellt der Online-Node eine unsigned PSBT. Diese wird offline geprueft, signiert und anschliessend wieder auf den Online-Node zum Broadcast uebertragen.
6. Uebertrage Deskriptoren und PSBTs nur ueber einen bewusst kontrollierten Pfad, zum Beispiel Wechseldatentraeger, und pruefe Dateinamen, Betrag, Zieladressen, Change-Ausgabe und Fee vor jeder Signatur.
7. Sichere im Server-Backup nur sanitisierte Konfiguration, Watch-only-Daten und Betriebsmetadaten. Seeds, `xprv`, `wallet.dat` und andere Private Keys bleiben in einem getrennten Offline-Backup.

## Gewaehlte Variante

Ich waehle `kleines Hot-Wallet + Watch-only + PSBT + Offline-Signierung` statt:

- `alles online auf einem Server`
- `eine gemeinsame Wallet fuer Payouts und Treasury`
- `vollstaendig manuellem Cold-only-Betrieb ohne Hot-Wallet`

Warum diese Variante:

- Sie reduziert den maximal gefaehrdeten Betrag bei einer Server-Kompromittierung.
- Sie ist fuer regelmaessige Auszahlungen praktikabler als ein rein manueller Cold-only-Prozess.
- Sie ist einfacher und realistischer als eine sofortige komplexe Multisig-Einfuehrung in einem kleinen Home-Lab.

## Begruendung der Korrektur

- Hot- und Cold-Rollen werden sauber getrennt.
- Watch-only wird als eigener Beobachtungs- und Vorbereitungs-Kontext eingefuehrt.
- PSBT und Offline-Signierung werden fuer Treasury-Transfers zwingend vorgeschrieben.
- Online-Seeds, `xprv`, `wallet.dat` und andere Private Keys sind ausdruecklich verboten.
- Backup-Pfade werden nach Sensitivitaet getrennt.

## Restrisiken

- Der Hot-Wallet-Kontext bleibt online angreifbar.
- Watch-only-Daten und Zahlungsmetadaten bleiben auf dem Online-System sichtbar.
- Ein kompromittierter Online-Node kann weiterhin manipulierte unsigned PSBTs vorbereiten; der Offline-Pruefschritt bleibt deshalb sicherheitskritisch.
- Spaetere Anforderungen koennen dennoch Multisig oder zusaetzliche Freigabeprozesse notwendig machen.
