# Review der fehlerhaften Artefakte

## Scope

- Geprueft wurden ausschliesslich die vier bereitgestellten Dateien.
- Es wurden keine Live-Aenderungen vorgenommen.
- Keine Konfiguration wurde produktiv ausgefuehrt.
- Der Fokus lag auf vorhandenen Fehlkonfigurationen und auf fehlenden Schutzmassnahmen.

## Gesamtbild

- Keine der vier Dateien enthaelt einen offensichtlichen Parserfehler im engeren Sinn.
- Die Probleme liegen fast vollstaendig in `Security`, `Deployability` und `Betrieb`.
- Die schwersten Muster sind:
  - unnötige Exponierung
  - Vermischung von Secret-Material mit normalen Betriebsartefakten
  - fehlende Segmentierung und fehlendes deny-by-default
  - fehlende Integritaets-, Retention- und Restore-Logik

## 1. `backup.bad.sh`

### Fundliste

| Prioritaet | Typ | Stelle | Befund | Kurzbewertung |
| --- | --- | --- | --- | --- |
| P1 | Security | Zeilen 9-13 | `var/lib/tor` und `var/lib/bitcoind` werden direkt mitgesichert. | Hidden-Service-Identitaeten, RPC-Cookies, Wallet-Dateien oder andere hochsensible Runtime-Artefakte koennen im Regelbackup landen. |
| P1 | Security | Zeilen 7 und 18 | Verzeichnis `0755`, Dateien `0644`. | Backups sind fuer andere lokale Nutzer lesbar. |
| P1 | Security | Gesamte Datei | Keine Verschluesselung der erzeugten Archive oder Dumps. | Ein Diebstahl des Backup-Ziels oder lokaler Lesezugriff genuegt fuer den Zugriff auf sensible Betriebsdaten. |
| P2 | Betrieb | Gesamte Datei | Kein Locking oder Sperrmechanismus gegen Parallelstarts. | Mehrere gleichzeitige Laeufe koennen Dateien ueberschreiben oder inkonsistente Artefakte erzeugen. |
| P2 | Betrieb | Zeile 4 | Fester Zielpfad `latest` ohne immutable Generationen. | Alte Sicherungen werden ueberschrieben; Wiederherstellung und Historie sind schlecht nachvollziehbar. |
| P2 | Security/Betrieb | Gesamte Datei | Keine Integritaetspruefung wie Hash-Manifest oder signierte Metadaten. | Manipulation oder partielle Korruption wird spaeter schwer erkennbar. |
| P2 | Betrieb | Gesamte Datei | Keine Retention-Logik. | Alte Artefakte wachsen unkontrolliert oder werden nur implizit durch Ueberschreiben entfernt. |
| P2 | Betrieb | Gesamte Datei | Kein dokumentierter Restore-Pfad und keine Restore-Hinweise. | Ein Backup ohne klaren Restore-Ablauf ist im Ernstfall nur begrenzt belastbar. |
| P2 | Betrieb | Zeilen 10 und 13 | Es wird direkt in die finalen Archivdateien geschrieben. | Bei einem Fehler bleiben unvollstaendige oder still inkonsistente Dateien unter gueltigem Namen liegen. |
| P2 | Deployability | Gesamte Datei | Keine Preflight-Pruefung fuer `pct`, `vzdump`, Gast-Existenz oder Zugriff. | Das Skript scheitert spaet und schlecht erklaerbar, wenn Voraussetzungen fehlen. |
| P2 | Betrieb | Zeile 16 | `vzdump` laeuft pauschal fuer Gast-IDs ohne dokumentierten Sensitivitaetsfilter. | Spaeter koennen ungewollt Vollbackups sensibler Rollen in denselben Backup-Pfad rutschen. |
| P3 | Betrieb | Zeile 2 | Nur `set -e`; `-u` und `pipefail` fehlen. | Defensive Fehlerbehandlung ist unvollstaendig. |
| P3 | Betrieb | Zeilen 10 und 13 | Live-Tar aus laufenden Gaesten ohne Quiesce oder Konsistenzfenster. | Konfigurationsarchive koennen formal lesbar, aber zeitlich inkonsistent sein. |

### Gewaehlte Korrekturvariante

Ich habe eine `sanitisierte, generationierte und am Ende verschluesselte Bundle-Variante` gewaehlt:

- sanitisierte Exporte fuer sensible Rollen
- Vollbackups nur fuer explizit freigegebene, niedrigere Sensitivitaet
- Locking, Integritaetsmanifest, Retention und Restore-Notizen
- finale Ausgabe nur als verschluesseltes Archiv

Alternative:

- Vollbackup aller Gaeste mit nachgelagerten Excludes

Diese Alternative ist weniger sicher, weil sensible Artefakte dabei zunaechst trotzdem entstehen und erst spaeter aussortiert werden muessten.

### Korrigierte Fassung

Siehe [backup.fixed.sh](</C:/Users/AK/Documents/Codex/2026-07-07/du-arbeitest-auf-einer-vorbereiteten-isolierten-2/outputs/korrigierte-artefakte/backup.fixed.sh>).

### Begruendung der Korrekturen

- `set -euo pipefail` und `flock` verbessern Robustheit und Parallelisierungsschutz.
- Zeitstempelverzeichnisse statt `latest` machen Retention und Restore nachvollziehbar.
- `EXCLUSIONS.txt` und `RESTORE-NOTES.txt` trennen sanitisierte Rebuild-Artefakte von nicht sicherbaren Geheimnissen.
- `var/lib/tor`, `var/lib/bitcoind`, Seeds, `xprv`, Wallets und Raw Keys bleiben ausdruecklich ausgeschlossen.
- `sha256sum` erzeugt ein Inhaltsmanifest fuer spaetere Integritaetspruefung.
- Das finale Bundle wird per `age` verschluesselt, statt offen auf dem Ziel zu liegen.
- Eine einfache Retention fuer alte verschluesselte Archive ist enthalten.

### Restrisiken

- Im Staging-Bereich liegen waehrend des Laufs temporaer unverschluesselte Artefakte auf dem Host.
- Auch sanitisierte Konfiguration kann noch Zugangsdaten oder Netzdetails enthalten.
- Die Integritaet des `age`-Empfaengers und des Offline-Schluesselmanagements ist ausserhalb des Skripts zu sichern.
- Eine echte Restore-Uebung ist im Skript nur vorbereitet, nicht automatisch validiert.

## 2. `bitcoin-flow.bad.md`

### Fundliste

| Prioritaet | Typ | Stelle | Befund | Kurzbewertung |
| --- | --- | --- | --- | --- |
| P1 | Security | Zeilen 5 und 9-14 | Hot- und Cold-Kontext sollen auf demselben Online-Server laufen. | Die Sicherheitsgrenze zwischen Zahlungsbetrieb und Langzeitverwahrung faellt weg. |
| P1 | Security | Zeilen 9-10 | Hot-Seed und Cold-Seed werden auf dem Online-Server erzeugt. | Bereits die Schluesselerzeugung findet im falschen Vertrauenskontext statt. |
| P1 | Security | Zeile 10 | Seeds sollen in `/root/wallet-seeds.txt` liegen. | Klare Online-Ablage sensibelster Geheimnisse im Klartext. |
| P1 | Security | Zeile 11 | Eine gemeinsame Wallet fuer Auszahlungen und Treasury. | Der komplette Bestand wird vom Online-System und seinen Kompromittierungen abhaengig. |
| P1 | Security | Zeile 12 | Bitcoin-Core-RPC wird ueber Onion fuer browsernahe Signierung veroeffentlicht. | Unnoetige Exponierung einer hochsensiblen Admin-/Signier-Schnittstelle. |
| P1 | Security | Zeile 13 | PSBT und Offline-Signierung werden bewusst verworfen. | Eine zentrale Schutzschicht fuer Treasury-Transfers wird abgeschafft. |
| P1 | Security/Betrieb | Zeile 14 | Seeds, Wallet-Daten und Onion-Dateien sollen im normalen Server-Backup auf demselben Host landen. | Ein einzelner Host- oder Backup-Kompromiss trifft Online- und Offline-Geheimnisse gleichzeitig. |
| P2 | Security | Gesamte Datei | Ein Watch-only-Kontext fehlt komplett. | Beobachtung, Bilanzierung und PSBT-Vorbereitung werden nicht von Spend-Rechten getrennt. |
| P2 | Security/Betrieb | Gesamte Datei | Kein definiertes Hot-Wallet-Limit und kein kontrollierter Refill-Prozess. | Der online gefaehrdete Betrag bleibt unbeschraenkt. |
| P2 | Security | Zeile 12 | Exponierungspfad und Admin-Pfad werden vermischt. | Nutzverkehr, Management und Signierung erhalten keine klare Trennung. |
| P2 | Betrieb | Gesamte Datei | Keine Integritaets- oder Plausibilitaetspruefung fuer transferierte PSBTs oder Deskriptoren. | Manipulierte unsigned PSBTs wuerden spaeter schwerer auffallen. |
| P2 | Betrieb | Gesamte Datei | Kein sauberer Backup-/Restore-Schnitt zwischen Online-Metadaten und Offline-Schluesseln. | Wiederherstellung und Geheimnisschutz sind nicht getrennt geplant. |

### Gewaehlte Korrekturvariante

Ich habe `kleines Hot-Wallet + Watch-only + PSBT + Offline-Signierung` gewaehlt.

Alternative:

- sofortiges Multisig-Design
- rein manueller Cold-only-Betrieb ohne Hot-Wallet

Warum ich die gewaehlte Variante bevorzuge:

- Sie ist deutlich sicherer als ein gemeinsamer Online-Wallet-Kontext.
- Sie bleibt fuer regelmaessige automatische Payouts realistisch betreibbar.
- Sie ist in einem kleinen Home-Lab einfacher korrekt umzusetzen als ein sofortiges komplexes Multisig-Setup.

### Korrigierte Fassung

Siehe [bitcoin-flow.fixed.md](</C:/Users/AK/Documents/Codex/2026-07-07/du-arbeitest-auf-einer-vorbereiteten-isolierten-2/outputs/korrigierte-artefakte/bitcoin-flow.fixed.md>).

### Begruendung der Korrekturen

- Cold-Secrets werden vollstaendig aus dem Online-System entfernt.
- Watch-only wird als eigener Rollenbaustein eingefuehrt.
- Treasury-Transfers laufen ausschliesslich ueber unsigned PSBT plus Offline-Signierung.
- RPC bleibt intern bzw. operator-only und wird nicht als Endnutzerpfad veroeffentlicht.
- Online- und Offline-Backups werden nach Sensitivitaet getrennt.

### Restrisiken

- Der Hot-Wallet-Kontext bleibt online kompromittierbar.
- Watch-only-Daten und Zahlungsmetadaten bleiben dem Online-System zugaenglich.
- Ein kompromittierter Online-Node kann weiterhin boesartige unsigned PSBTs vorbereiten; menschliche Offline-Pruefung bleibt entscheidend.
- Hoeherwertige Treasury-Anforderungen koennen spaeter dennoch Multisig oder organisatorische Mehr-Augen-Freigaben erfordern.

## 3. `docker-compose.bad.yml`

### Fundliste

| Prioritaet | Typ | Stelle | Befund | Kurzbewertung |
| --- | --- | --- | --- | --- |
| P1 | Security | Zeile 5 | `vaultwarden` laeuft `privileged`. | Unnoetige Vollprivilegien in einem Passwortdienst sind nicht vertretbar. |
| P1 | Security | Zeile 14 | Docker-Socket wird in `vaultwarden` eingereicht. | Ein App-Kompromiss kann in Host- oder Container-Kontrolle eskalieren. |
| P1 | Security | Zeilen 7, 25 und 38 | `vaultwarden`, `grafana` und `blackbox-exporter` werden breit auf Host-Ports exponiert. | Interne oder operator-only-Dienste werden unnoetig nach aussen veroeffentlicht. |
| P1 | Security | Zeile 9 | `DOMAIN` nutzt klares HTTP auf einer IP-Adresse. | Zugriffspfad und Cookie-/Token-Schutz sind fuer einen Passwortdienst zu schwach. |
| P1 | Security | Zeilen 10-12 | Offene Registrierungen, Einladungen und ein hart kodierter `ADMIN_TOKEN`. | Account-Missbrauch und Secret-Leak sind praktisch vorprogrammiert. |
| P1 | Security | Zeilen 27-30 | Grafana erlaubt anonyme Nutzung, Self-Signup und nutzt ein triviales Admin-Passwort. | Operator-only-Daten werden breit oeffentlich. |
| P1 | Security | Zeilen 37-44 | `blackbox-exporter` ist offen exponiert. | Exponierte Probe-Endpunkte koennen fuer SSRF oder internes Scanning missbraucht werden. |
| P2 | Deployability | Zeilen 16-18 und 46-47 | `vaultwarden` referenziert `frontend`, definiert ist aber nur `internal`. | Das File ist so nicht deploybar. |
| P2 | Security/Deployability | Zeilen 3, 21 und 35 | Durchgaengig `:latest`. | Keine reproduzierbaren Deployments, hohes Drift- und Supply-Chain-Risiko. |
| P2 | Security/Betrieb | Zeilen 16-18 | `vaultwarden` haengt gleichzeitig an einer oeffentlichen und einer internen Zone. | Selbst bei korrekt definiertem `frontend` entstuende ein unnötiger Brueckenkopf fuer laterale Bewegung. |
| P2 | Betrieb | Zeile 23 | `grafana` laeuft explizit als Root. | Unnoetige Rechte vergroessern den Schadensradius. |
| P2 | Betrieb | Zeilen 20-32 | Grafana hat kein persistentes Datenvolume. | Dashboards, lokale Datenquellen und Admin-Zustand sind bei Neuaufbau nicht belastbar. |
| P2 | Security | Zeile 30 | Grafana-Telemetrie ist aktiv. | Unnoetiger Metadatenabfluss nach aussen. |
| P3 | Security | Gesamte Datei | Es fehlen Hardening-Massnahmen wie `no-new-privileges`, `cap_drop`, `read_only` oder restriktive Bindings. | Fehlende Schutzmassnahmen vergroessern die Angriffsoberflaeche. |
| P3 | Betrieb | Gesamte Datei | Keine Healthchecks oder klaren Robustheitsmechanismen auf Compose-Ebene. | Fehler werden spaeter spaerlicher und weniger gezielt sichtbar. |

### Gewaehlte Korrekturvariante

Ich habe die `localhost-only + ein internes Netz + externe Secret-Injektion + reduziertes Container-Hardening`-Variante gewaehlt.

Alternative:

- gar keine Host-Ports und Zugriff ausschliesslich ueber einen separaten Reverse Proxy

Warum ich die gewaehlte Variante bevorzuge:

- Sie ist deutlich sicherer als breit veroeffentlichte Host-Ports.
- Sie bleibt ohne zusaetzlichen Proxy deploybar.
- Sie vermeidet Klartext-Secrets im Compose-File.

### Korrigierte Fassung

Siehe [docker-compose.fixed.yml](</C:/Users/AK/Documents/Codex/2026-07-07/du-arbeitest-auf-einer-vorbereiteten-isolierten-2/outputs/korrigierte-artefakte/docker-compose.fixed.yml>).

### Begruendung der Korrekturen

- `privileged` und Docker-Socket-Mount wurden entfernt.
- Alle Dienste binden nur noch an `127.0.0.1`.
- Unnoetige Registrierungen, anonyme Nutzung und Telemetrie wurden deaktiviert.
- Image-Referenzen muessen jetzt explizit ausserhalb der Datei gesetzt werden.
- Das Netzdesign wurde auf ein konsistentes internes Netz reduziert.
- `grafana` bekommt ein persistentes Volume und laeuft nicht mehr als Root.
- `cap_drop`, `no-new-privileges`, `read_only` und `tmpfs` ziehen die Privilegienbasis enger.

### Restrisiken

- Auch `127.0.0.1` schuetzt nicht gegen einen kompromittierten Host.
- Ohne echte Secret-Dateien oder einen Secret-Store bleibt die sichere Injektion organisatorisch sensibel.
- Pinned Tags sind besser als `latest`, aber echte Digests waeren noch belastbarer.
- Healthchecks fehlen weiterhin; die Datei ist gehaertet, aber nicht vollstaendig betriebsoptimiert.

## 4. `firewall.bad.nft`

### Fundliste

| Prioritaet | Typ | Stelle | Befund | Kurzbewertung |
| --- | --- | --- | --- | --- |
| P1 | Security | Zeilen 2-9 | `input` hat `policy accept`. | Das ist kein deny-by-default-Ansatz. |
| P1 | Security | Zeile 9 | `22`, `80`, `443`, `111`, `3128` und `8006` sind fuer beliebige Quellen offen. | Management- und Infrastrukturdienste werden breit exponiert. |
| P1 | Security | Gesamte Datei | Durch `table inet` gilt die Freigabe fuer IPv4 und potenziell auch fuer IPv6. | Die Exponierung ist breiter als in vielen Home-Labs erwartet. |
| P1 | Security | Zeilen 12-19 | `forward` hat ebenfalls `policy accept`. | Die expliziten Forward-Regeln begrenzen den Verkehr faktisch nicht. |
| P1 | Security | Zeilen 16-17 | `vmbr1` und `vmbr2` duerfen sich gegenseitig frei erreichen. | Laterale Bewegung zwischen Infrastruktur- und Service-Zone ist direkt erlaubt. |
| P1 | Security/Betrieb | Zeilen 18-19 | `vmbr1` und `vmbr2` duerfen beliebig zu `vmbr0` weiterleiten. | Unkontrollierte Nord-Sued-Verbindungen und offener Egress. |
| P2 | Security | Gesamte Datei | Keine Quellbindung fuer Management-Zugriffe. | Admin-Pfade sind nicht auf bekannte Operator-Quellen verengt. |
| P2 | Security | Gesamte Datei | Keine Anti-Spoofing- oder Plausibilitaetspruefung fuer Quellen. | Falsche interne Quelladressen werden nicht gesondert behandelt. |
| P2 | Betrieb | Gesamte Datei | Kein Logging, keine Sets und keine klaren Variablen fuer Zonen und Admin-Pfade. | Das Regelwerk ist spaeter schwerer wartbar und driftet leichter. |
| P3 | Betrieb | Zeilen 6-9 und 16-19 | Die wenigen expliziten Regeln suggerieren Kontrolle, obwohl die Default-Policies alles erlauben. | Das erhoeht das Risiko falscher Annahmen im Betrieb. |

### Gewaehlte Korrekturvariante

Ich habe eine `deny-by-default + explizite Admin-Quellen + minimale Ost-West- und Egress-Freigaben`-Variante gewaehlt.

Alternative:

- ein generischer Platzhalter ohne konkrete Quellen oder Portgruppen

Warum ich die gewaehlte Variante bevorzuge:

- Sie ist besser pruefbar.
- Sie reduziert spaetere Drift.
- Sie bildet das eigentliche Zielbild einer segmentierten Home-Lab-Firewall konkreter ab.

### Korrigierte Fassung

Siehe [firewall.fixed.nft](</C:/Users/AK/Documents/Codex/2026-07-07/du-arbeitest-auf-einer-vorbereiteten-isolierten-2/outputs/korrigierte-artefakte/firewall.fixed.nft>).

### Begruendung der Korrekturen

- `policy drop` macht `input` und `forward` zu echten Filterketten.
- Host-Admin-Zugriffe sind auf definierte Quelladressen und wenige Ports beschraenkt.
- Die breite Freigabe von `111`, `3128`, `80`, `443` und `8006` auf allen Interfaces entfällt.
- Laterale Bewegung zwischen `infra` und `service` wird auf definierte Web-Pfade reduziert.
- Basis-Egress wird auf DNS, NTP und HTTP(S) begrenzt.
- Sets und `define`-Variablen machen das Regelwerk wartbarer.

### Restrisiken

- Die gewaehlten IPs und Bridge-Namen sind Annahmen und muessen zur realen Umgebung passen.
- Ohne NAT-, Logging-, Rate-Limit- oder feinere IPv6-Regeln ist das noch kein vollstaendiges Produktionsregelwerk.
- Anti-Spoofing ist nur indirekt verbessert; ein strengeres Produktionsregelwerk wuerde hier noch weiter gehen.

## Fazit

- Das groesste Risiko in den Artefakten ist nicht Syntax, sondern fehlende Sicherheitsdisziplin.
- Die korrigierten Referenzfassungen bevorzugen:
  - minimale Exponierung
  - minimierte Privilegien
  - Trennung von Online- und Offline-Geheimnissen
  - deny-by-default statt impliziter Offenheit
  - Integritaets-, Locking-, Retention- und Restore-Bausteine fuer Backups
