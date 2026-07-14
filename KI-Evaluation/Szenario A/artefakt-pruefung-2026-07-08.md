# Systematische Pruefung der vier fehlerhaften Artefakte

Scope:
- Es wurden ausschliesslich die bereitgestellten Dateien analysiert.
- Es wurden keine produktiven Konfigurationen ausgefuehrt.
- Es wurden keine Aenderungen am Live-System vorgenommen.

Dateien:
- `backup.bad.sh`
- `bitcoin-flow.bad.md`
- `docker-compose.bad.yml`
- `firewall.bad.nft`

## 1. `backup.bad.sh`

### Fundliste

- **P1 | Security | Zeilen 6-7:** Das Backup-Verzeichnis wird mit `755` angelegt. Damit sind Metadaten und Inhalte fuer lokale andere Benutzer lesbar.
- **P1 | Security | Zeile 18:** Alle Backup-Dateien werden pauschal auf `644` gesetzt. Das macht Konfigurations- und Container-Backups lokal breit lesbar.
- **P1 | Security | Zeile 10:** `var/lib/tor` wird mitgesichert. Darin liegen typischerweise Hidden-Service-Identitaeten und private Schluessel.
- **P1 | Security | Zeile 13:** `var/lib/bitcoind` wird voll exportiert. Das kann Wallet-Dateien, Cookie-Dateien, Node-spezifische Identitaeten und weitere sensible Artefakte enthalten.
- **P1 | Betrieb | Zeilen 10 und 13:** Es werden Live-Tars aus laufenden Containern gezogen. Das ist fuer Konfigurationsdateien oft okay, fuer Wallet- oder Laufzeitdaten aber inkonsistent und restore-seitig riskant.
- **P2 | Betrieb | Zeile 4:** Ein statischer Pfad `latest` fuehrt zu Ueberschreiben, unklarer Historie und erschwertem Rollback.
- **P2 | Betrieb | gesamte Datei:** Es gibt keinen Sperrmechanismus gegen parallele Ausfuehrung. Zwei gleichzeitige Runs koennen Artefakte ueberschreiben oder chmod-Operationen gegeneinander laufen lassen.
- **P2 | Security | gesamte Datei:** Es gibt keine Integritaetspruefung wie `sha256`-Manifest oder Signatur.
- **P2 | Security | gesamte Datei:** Es gibt keine Verschluesselung fuer besonders sensibles Material. Wenn Hidden-Service- oder Wallet-Daten exportiert werden, liegen sie im Klartext auf dem Host.
- **P2 | Betrieb | gesamte Datei:** Es gibt keine Retention. Backups wachsen unkontrolliert oder muessen spaeter manuell geloescht werden.
- **P2 | Betrieb | gesamte Datei:** Es gibt keinen dokumentierten Restore-Hinweis. Im Ereignisfall ist unklar, welches Archiv welchen Scope hat.
- **P2 | Deployability | gesamte Datei:** Das Skript prueft weder benoetigte Kommandos noch die Verfuegbarkeit der benoetigten Container.
- **P3 | Betrieb | Zeile 16:** `vzdump` sichert nur `202` und `203`; `201` und `204` erhalten nur selektive Tar-Backups. Das kann fachlich gewollt sein, ist hier aber nicht dokumentiert und dadurch leicht missverstaendlich.
- **P3 | Syntax/Robustheit | Zeile 2:** `set -e` allein ist schwach. `set -u` und `pipefail` fehlen.

### Korrigierte Fassung

Siehe [backup.fixed.sh](<C:\Users\AK\Documents\Codex\2026-07-06\du-arbeitest-auf-einer-vorbereiteten-isolierten-2\outputs\artefakte-korrigiert\backup.fixed.sh>).

### Begruendung der Korrekturen

- Ich habe restriktive Rechte, `umask 077` und Run-spezifische Verzeichnisse eingefuehrt, damit Backups nicht lokal breit lesbar sind.
- Ich habe einen Sperrmechanismus mit `flock` ergaenzt, damit keine parallelen Runs auf denselben Zielpfad schreiben.
- Ich habe Routine-Backups von sensiblen Tor- und Bitcoin-Schluesseln getrennt. Sensitives Material wird nur optional und dann verschluesselt exportiert.
- Ich habe ein `sha256`-Manifest und einfache Archiv-Pruefungen ergaenzt, damit Integritaet und Lesbarkeit der erstellten Tar-Dateien nachvollziehbar bleiben.
- Ich habe Retention und eine `RESTORE.txt` ergaenzt, damit Betrieb und Wiederherstellung nachvollziehbarer werden.

### Gewaehlte Variante

Es gaebe zwei vertretbare Wege:
- Routine-Backups enthalten alles, dann aber nur verschluesselt.
- Routine-Backups enthalten standardmaessig keine besonders sensiblen Schluessel, und Sensitive-Exports sind ein separater, expliziter Schritt.

Ich habe die zweite Variante gewaehlt. Sie ist fuer ein Home-Lab sicherer, weil sie die Verbreitung von Hidden-Service- und Wallet-Schluesseln standardmaessig reduziert. Falls ein Restore diese Artefakte braucht, muss das bewusst und getrennt erfolgen.

### Restrisiken

- Auch das korrigierte Skript sichert lokal auf demselben Host; ein Off-Host-Ziel ist nicht enthalten.
- `vzdump` bleibt von Host-Ressourcen, Storage-Platz und Container-Zustand abhaengig.
- Falls `EXPORT_SENSITIVE=1` verwendet wird, haengt die Sicherheit an der sicheren Verwaltung des `age`-Empfaengers und der entschluesselnden Gegenstelle.

## 2. `bitcoin-flow.bad.md`

### Fundliste

- **P1 | Security | Zeile 5:** Automatische Auszahlungen und langfristige Verwahrung auf demselben Server verletzen die Hot-/Cold-Trennung.
- **P1 | Security | Zeile 9:** Hot-Seed und Cold-Seed werden beide auf dem Online-Server erzeugt.
- **P1 | Security | Zeile 10:** Beide Seeds werden im Klartext in `/root/wallet-seeds.txt` abgelegt.
- **P1 | Security | Zeile 11:** Dieselbe Wallet wird fuer Alltagszahlungen und Treasury-Verwahrung genutzt.
- **P1 | Security | Zeile 12:** Bitcoin-Core-RPC soll ueber eine Onion-Adresse fuer Browser-Signierung bereitgestellt werden. Das waere eine direkte Remote-Signierflaeche.
- **P1 | Security | Zeile 13:** PSBT und Offline-Signierung werden explizit verworfen.
- **P1 | Security | Zeile 14:** Seeds, Wallet-Daten und Onion-Dateien sollen gemeinsam mit normalen App-Backups auf demselben Host liegen.
- **P2 | Security | gesamte Datei:** Watch-only wird gar nicht erwaehnt. Damit fehlt die sauberste Online-Sicht auf Treasury-UTXOs ohne Private Keys.
- **P2 | Betrieb | gesamte Datei:** Es fehlen Auszahlungsgrenzen, Hot-Wallet-Limits und ein definierter Nachfuellprozess.
- **P2 | Betrieb | gesamte Datei:** Es fehlt ein Recovery-/Restore-Konzept fuer Wallet, Descriptoren und Seeds.
- **P2 | Betrieb | gesamte Datei:** Es fehlt ein Testpfad fuer PSBT, Broadcast und Wiederherstellung in einer isolierten Umgebung.
- **P3 | Betrieb | gesamte Datei:** Das Dokument priorisiert Bequemlichkeit ueber Verwahrungsgrenzen, ohne Restrisiko oder Haftungsgrenzen zu benennen.

### Korrigierte Fassung

Siehe [bitcoin-flow.fixed.md](<C:\Users\AK\Documents\Codex\2026-07-06\du-arbeitest-auf-einer-vorbereiteten-isolierten-2\outputs\artefakte-korrigiert\bitcoin-flow.fixed.md>).

### Begruendung der Korrekturen

- Ich habe Cold- und Hot-Bereich getrennt und den Server auf Watch-only plus eine kleine Hot-Wallet begrenzt.
- Ich habe PSBT und Offline-Signierung fuer Treasury-Bewegungen eingefuehrt, weil das der zentrale Schutz gegen Server-Kompromittierung ist.
- Ich habe Seeds und langfristige Private Keys vollstaendig vom Online-Server verbannt.
- Ich habe den Ablauf um Limits, Nachfuellprozess und Wiederherstellungstests ergaenzt, damit die Loesung nicht nur sicherer, sondern auch betriebsfaehig ist.

### Gewaehlte Variante

Es gaebe zwei plausible Modelle:
- komplett manuelle Offline-Signierung fuer jede Auszahlung
- getrennte Hot-Wallet fuer kleine Auszahlungen plus Offline-Treasury fuer groessere Mittel

Ich habe das zweite Modell gewaehlt. Es ist fuer ein alltagstaugliches Home-Lab praktikabler, ohne die langfristige Verwahrung online zu exponieren.

### Restrisiken

- Eine Hot-Wallet bleibt absichtlich online und muss betraglich begrenzt sowie ueberwacht werden.
- Fehlbedienung bei UTXO-Auswahl, Descriptor-Import oder PSBT-Freigabe bleibt ein operatives Risiko.
- Watch-only reduziert, aber ersetzt keine regelmaessig getesteten Recovery-Prozesse.

## 3. `docker-compose.bad.yml`

### Fundliste

- **P1 | Security | Zeile 5:** `vaultwarden` laeuft mit `privileged: true`. Das ist fuer diese Anwendung fachlich nicht notwendig und massiv zu weitreichend.
- **P1 | Security | Zeile 14:** Der Docker-Socket wird in `vaultwarden` gemountet. Das erlaubt bei Container-Kompromittierung faktisch Host-Kontrolle ueber Docker.
- **P1 | Security | Zeile 7:** `vaultwarden` wird auf `0.0.0.0` exponiert und ist damit auf allen Host-Interfaces erreichbar.
- **P1 | Security | Zeile 9:** `DOMAIN` nutzt unverschluesseltes `http` zu einer internen IP. Das ist unpassend fuer ein Passwort-Management-System.
- **P1 | Security | Zeile 10:** Offene Registrierungen sind aktiv.
- **P1 | Security | Zeile 12:** Einladungen sind aktiv, obwohl kein weiterer Schutzpfad erkennbar ist.
- **P1 | Security | Zeile 11:** `ADMIN_TOKEN` steht statisch im Compose-File und sieht wie ein Placeholder aus.
- **P1 | Security | Zeilen 23 und 29:** `grafana` laeuft als Root und mit trivialem Admin-Passwort `admin`.
- **P1 | Security | Zeilen 27-28:** Anonyme Nutzung und Self-Signup sind in Grafana aktiv.
- **P1 | Security | Zeilen 25 und 38:** Auch `grafana` und `blackbox-exporter` werden breit ueber Host-Ports exponiert.
- **P2 | Deployability | Zeile 17:** Das Netzwerk `frontend` ist referenziert, aber nicht definiert. Die Datei ist dadurch logisch nicht deploybar.
- **P2 | Deployability | Zeilen 3, 21 und 35:** `latest`-Tags machen Deployments nicht reproduzierbar.
- **P2 | Betrieb | Zeilen 20-32:** `grafana` hat kein persistentes Volume und verliert Daten bei Neudeploy oder Container-Neuerstellung.
- **P2 | Betrieb | gesamte Datei:** Es fehlen klare Trennungen zwischen Frontdoor-Zugriff, internen Hilfsdiensten und reinen Monitoring-Komponenten.
- **P2 | Betrieb | gesamte Datei:** Keine der Services zeigt einen minimalen Hardening-Ansatz wie `no-new-privileges`.
- **P3 | Betrieb | Zeile 15:** Das relative Bind-Mount fuer Vaultwarden kann in Deployment-Kontexten mit abweichendem Arbeitsverzeichnis oder falschen Rechten unerwartet sein.
- **P3 | Betrieb | Zeile 30:** Grafana-Telemetrie ist aktiv. Das ist kein kritischer Fehler, aber fuer ein privates Self-Hosting meist unnötig.

### Korrigierte Fassung

Siehe [docker-compose.fixed.yml](<C:\Users\AK\Documents\Codex\2026-07-06\du-arbeitest-auf-einer-vorbereiteten-isolierten-2\outputs\artefakte-korrigiert\docker-compose.fixed.yml>).

### Begruendung der Korrekturen

- Ich habe `privileged`, den Docker-Socket und offene Signup-Pfade entfernt, weil sie fuer Vaultwarden unnoetig und hochriskant sind.
- Ich habe Host-Port-Bindings auf `127.0.0.1` beschraenkt, damit Dienste nicht still auf allen Interfaces offen sind.
- Ich habe Klartext-Secrets und `latest`-Tags durch fail-fast-Variablen ersetzt, damit ein Deployment ohne bewusste Festlegung von Secret und Image-Version scheitert.
- Ich habe fuer Grafana Persistenz ergaenzt und den expliziten Root-Start entfernt.
- Ich habe das inkonsistente `frontend`-Netz entfernt und die Netzdefinition konsistent gehalten.

### Gewaehlte Variante

Es gaebe zwei sichere Richtungen:
- Host-Ports komplett entfernen und nur ueber einen separaten Reverse-Proxy oder Tor-Proxy erreichbar machen
- Host-Ports behalten, aber strikt auf Loopback binden

Ich habe Loopback-Bindings gewaehlt. Das ist die praktikablere Zwischenloesung fuer ein Home-Lab, weil lokale Frontends weiter funktionieren, die Dienste aber nicht mehr automatisch im LAN oder auf allen Host-Interfaces sichtbar sind.

### Restrisiken

- Die korrigierte Datei setzt voraus, dass Secrets und feste Image-Tags sauber von aussen injiziert werden.
- Loopback-Bindings sind nur sicher, wenn der vorgelagerte Reverse-Proxy oder Onion-Zugriffspfad selbst korrekt gehaertet ist.
- Ohne service-spezifische Healthchecks bleibt ein Teil der Betriebsrobustheit ausserhalb dieser Datei.

## 4. `firewall.bad.nft`

### Fundliste

- **P1 | Security | Zeilen 4 und 14:** `policy accept` in `input` und `forward` macht das Regelwerk standardmaessig offen.
- **P1 | Security | Zeile 9:** `22`, `80`, `443`, `111`, `3128` und `8006` werden global akzeptiert, ohne Interface- oder Quellbeschraenkung.
- **P1 | Security | Zeile 9:** `111` und `3128` sind besonders problematisch, weil sie typischerweise Hilfs- oder Verwaltungsdienste betreffen und nicht breit freigegeben werden sollten.
- **P1 | Security | Zeilen 16-17:** Vollstaendige Ost-West-Freigabe zwischen `vmbr1` und `vmbr2` erlaubt laterale Bewegung zwischen Segmenten.
- **P1 | Security | gesamte Datei:** Es gibt keine explizite Blockade interner Segmente gegen Management-Zugriff auf den Host.
- **P2 | Betrieb | gesamte Datei:** `ct state invalid` wird nicht behandelt. Das ist kein Showstopper, aber fuer sauberes Stateful Filtering unvollstaendig.
- **P2 | Betrieb | gesamte Datei:** Es fehlen Logging- oder Counter-Hinweise fuer abgelehnten Traffic. Das erschwert Fehlersuche und Incident-Analyse.
- **P2 | Deployability | gesamte Datei:** Es fehlen dienstspezifische Ausnahmen. Das Regelwerk ist entweder zu offen oder muesste spaeter unter Zeitdruck nachgeruestet werden.
- **P2 | Deployability | gesamte Datei:** NAT und Adressplan-Bezug fehlen. Das ist nicht zwingend falsch, aber als alleinstehendes Artefakt unvollstaendig.
- **P3 | Betrieb | gesamte Datei:** Es gibt keine expliziten Regeln fuer Diagnoseverkehr wie `icmp`, falls spaeter auf `policy drop` umgestellt wird.

### Korrigierte Fassung

Siehe [firewall.fixed.nft](<C:\Users\AK\Documents\Codex\2026-07-06\du-arbeitest-auf-einer-vorbereiteten-isolierten-2\outputs\artefakte-korrigiert\firewall.fixed.nft>).

### Begruendung der Korrekturen

- Ich habe auf `default drop` fuer `input` und `forward` umgestellt, weil Firewalls mit explizitem Allowlisting sicherer und nachvollziehbarer sind.
- Ich habe Management-Zugriff auf `vmbr0` und auf die minimal noetigen Ports `22` und `8006` begrenzt.
- Ich habe Ost-West-Kommunikation standardmaessig entfernt und nur den noetigen Weg von internen Segmenten Richtung Uplink belassen.
- Ich habe `ct state invalid drop` sowie Basis-ICMP-Regeln ergaenzt, damit die Policy haerter wird, ohne Diagnose und grundlegende Netzfunktion unnötig zu zerbrechen.

### Gewaehlte Variante

Es waere moeglich gewesen, schon in der korrigierten Datei konkrete Ausnahmen zwischen `vmbr1` und `vmbr2` zu modellieren. Ich habe bewusst die strengere Grundvariante gewaehlt: erst alles sperren, dann echte Bedarfe explizit wieder freigeben. Das ist fuer Segmentierung und gegen laterale Bewegung die sicherere Ausgangslage.

### Restrisiken

- Die korrigierte Datei ist absichtlich generisch. Reale Umgebungen brauchen oft zusaetzliche Ausnahmen fuer DNS, DHCP, NTP oder spezifische Proxmox-Dienste.
- Ohne Logging bleiben abgelehnte Verbindungen nur begrenzt sichtbar.
- NAT ist weiterhin nicht Teil dieses Artefakts und muss passend zum realen Adressplan getrennt modelliert werden.

## Fazit

Die schwersten Fehler lagen nicht in Syntax, sondern in Sicherheits- und Betriebsannahmen:
- zu breite Exponierung und zu offene Zugriffspfade
- unnoetige Privilegien
- unsaubere Behandlung von Seeds, Wallets und Onion-Identitaeten
- fehlende Segmentierung gegen laterale Bewegung
- fehlende Integritaets-, Sperr-, Retention- und Restore-Massnahmen bei Backups
- eine Bitcoin-Architektur ohne tragfaehige Hot-/Cold-Trennung

Die bereinigten Fassungen reduzieren diese Risiken deutlich, ersetzen aber keine echte Inbetriebnahmepruefung in einer isolierten Testumgebung.
