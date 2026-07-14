# Self-Audit `ailab1` vom 2026-07-06

Read-only Audit. Es wurden nur Prüfungen per SSH auf `ailab1` und per `pct exec` in den Containern durchgeführt. Es wurden keine Konfigurationsänderungen umgesetzt.

## Befunde

### P1: Der Proxmox-Host selbst ist operativ ein Blind Spot
- **Befund:** `ailab1` selbst wird nicht von Prometheus überwacht. In den aktiven Targets fehlen Host-Metriken komplett, obwohl bei den letzten Backups bereits Thin-Pool-Warnungen aufgetreten sind.
- **Belege:** `work/services/ops/config/prometheus/prometheus.yml:25-31`; Backup-Log aus `/var/lib/homelab-backups/runs/20260706-224115/run.log` mit Thin-Pool-Warnungen.
- **Risiko:** Host-Speicher- oder IO-Probleme treffen alle Services gleichzeitig, bleiben aber bis zum Ausfall oder bis zum Backup-Fehler unsichtbar.
- **Empfohlene Korrektur:** Host-Monitoring ergänzen, idealerweise mit Node Exporter auf dem Host oder einem Proxmox-spezifischen Exporter; dazu Alerts für Thin-Pool-Auslastung, Root-Filesystem, RAM, Load und Backup-Fehler.

### P1: Interne Ost-West-Zugriffe sind deutlich offener als für ein Tor-zentriertes Setup nötig
- **Befund:** Zwischen den Containern sind `sshd` auf Port `22` und `node-exporter` auf Port `9100` weitgehend direkt erreichbar. Zusätzlich kann `tor-edge` fast alle veröffentlichten App- und Ops-Ports direkt ansprechen.
- **Belege:** Laufzeit-Scans zwischen `201`, `202`, `203`, `204`; Docker-Firewall-Regeln schützen nur `DOCKER-USER`, nicht generische Container-Ports: `work/services/app-core/homelab-docker-firewall.sh:6-16`, `work/services/ops/homelab-docker-firewall.sh:6-15`.
- **Risiko:** Ein kompromittierter Container hat unnötig viele Recon- und Pivot-Möglichkeiten. Das widerspricht dem Ziel, Dienste primär nur über Tor verfügbar zu machen.
- **Empfohlene Korrektur:** Container-Input-Policies pro CT ergänzen. `sshd` nur von einer klar definierten Management-Quelle erlauben. `node-exporter` nur für Prometheus freigeben. App- und Ops-Ports intern nur für `tor-edge` oder explizit benötigte Gegenstellen erlauben.

### P1: Host-SSH ist unnötig schwach für das aktuelle Bedrohungsmodell
- **Befund:** Auf dem Host ist effektiv `PermitRootLogin yes` und `PasswordAuthentication yes` aktiv.
- **Belege:** Laufzeitprüfung am 2026-07-06 mit `sshd -T` auf `ailab1`: `permitrootlogin yes`, `passwordauthentication yes`, `pubkeyauthentication yes`.
- **Risiko:** Passwortbasierter Root-Zugang ist für einen Internet-nahen Virtualisierungshost ein unnötig starker Angriffsvektor, selbst wenn der Zugriff aktuell nur lokal weitergeleitet wird.
- **Empfohlene Korrektur:** Root-Login per Passwort auf dem Host deaktivieren und Management-Zugriff auf einen dedizierten Admin-Workflow begrenzen. Falls die Vorgabe "Zugang nicht ändern" bestehen bleibt, diesen Punkt als bewusst akzeptiertes Restrisiko dokumentieren.

### P1: Das Bitcoin-Setup ist noch nicht alltagstauglich für echte Transaktionen
- **Befund:** Der Node ist noch tief in der Initial Block Download Phase, es existiert keine geladene Wallet, und es gibt keinen validierten Bedienpfad für Alltagszahlungen.
- **Belege:** Laufzeitstatus von `bitcoin-cli`: `blocks=288893`, `headers=956952`, `initialblockdownload=true`, `verificationprogress≈0.02479`; `listwallets` leer; `walletdir` leer.
- **Risiko:** Das Setup wirkt wie ein Bitcoin-Bereich, ist aber praktisch noch kein belastbarer Transaktions-Stack. Falsche Erwartungshaltung wäre hier ein Sicherheits- und Betriebsrisiko.
- **Empfohlene Korrektur:** Bitcoin-Bereich explizit in Phasen trennen: Node-Sync abschließen, Wallet-Konzept festlegen, Recovery testen, Spend-Workflow dokumentieren, erst danach als produktionsnah einstufen.

### P2: Backup deckt Host-Ausfall und Host-Kompromittierung nicht ab
- **Befund:** Backups liegen ausschließlich lokal auf demselben Proxmox-Host. `202` und `203` werden als LXC-Snapshots gesichert, `201` und `204` nur selektiv als tar-basierte Konfigurations- und Identitäts-Backups.
- **Belege:** `work/scripts/homelab-backup.sh:31-34`, `work/scripts/homelab-backup.sh:49-62`, `work/scripts/homelab-backup.sh:70-81`, `work/scripts/homelab-backup.sh:83-107`; aktuelle Artefakte unter `/var/lib/homelab-backups/runs/20260706-224115`.
- **Risiko:** Gegen versehentliche Servicefehler ist das hilfreich, gegen Host-Defekt, Storage-Korruption oder vollständige Host-Kompromittierung aber unzureichend.
- **Empfohlene Korrektur:** Zweites Sicherungsziel außerhalb des Hosts ergänzen. Für `btc-node` klare Entscheidung treffen, ob nur Konfiguration oder vollständige Wallet-/Node-Recovery im Scope ist.

### P2: Alerting ist technisch vorhanden, aber für den Betreiber noch nicht belastbar
- **Befund:** Alertmanager liefert lokal an den Forwarder, `ntfy` verarbeitet Nachrichten, aber Uptime Kuma hat aktuell `0` Notification-Definitionen. Damit existiert kein nachweislich getesteter, betreiberseitiger Alarmweg.
- **Belege:** Uptime-Kuma-Datenbankstatus `monitor_notification = 0`; Logs von `ops-alert-forwarder-1` mit erfolgreichen `POST /alertmanager`; Logs von `ops-ntfy-1` mit steigenden `messages_published`.
- **Risiko:** Im Fehlerfall können Alarme intern generiert werden, ohne zuverlässig auf einem Endgerät oder einem zweiten Kanal anzukommen.
- **Empfohlene Korrektur:** Mindestens einen getesteten Betreiberkanal definieren und Testalarme auslösen. Zusätzlich Eskalationspfad für "Prometheus down" oder "ntfy down" ergänzen.

### P2: Metrik-Endpunkte sind unnötig breit einsehbar
- **Befund:** `node-exporter` auf `201`, `202` und `203` ist von allen Containern aus erreichbar. Auf `204` ist Port `9100` immerhin nur von `203` freigegeben.
- **Belege:** Laufzeit-Connectivity-Tests zwischen allen CTs; BTC-Firewall als positives Gegenbeispiel in `work/services/btc-node/homelab-btc-firewall.sh:5-17`.
- **Risiko:** Metriken liefern Prozess-, Kernel- und Ressourcendaten und sind für Recon in einem kompromittierten Container nützlich.
- **Empfohlene Korrektur:** Exporter-Endpunkte nur von Prometheus zulassen. Optional Exporter an interne Loopback/Proxy-Pfade binden.

### P2: Standardnahe Admin-Benutzernamen bleiben unnötig vorhersehbar
- **Befund:** Mehrere Deploy-Defaults verwenden generische Admin-Usernamen wie `admin` oder `gitadmin`.
- **Belege:** `work/scripts/deploy-homelab-services.sh:31`, `work/scripts/deploy-homelab-services.sh:35`, `work/scripts/deploy-homelab-services.sh:41`, `work/scripts/deploy-homelab-services.sh:48`, `work/scripts/deploy-homelab-services.sh:60`.
- **Risiko:** Das ist kein kritischer Einzelbefund, reduziert aber die Entropie bei Login-Versuchen und erschwert saubere Trennung zwischen Betreiber- und App-Accounts.
- **Empfohlene Korrektur:** Nicht-generische Benutzernamen verwenden oder zentrale Anmeldung mit klaren Rollennamen planen, sobald der Scope das zulässt.

### P2: Secrets sind zwar geschützt, aber stark konzentriert
- **Befund:** Viele produktive Secrets liegen im Klartext in `/root/homelab-secrets/*.env`. Die Dateirechte sind korrekt restriktiv, die Konzentration auf dem Host bleibt aber ein Single Point of Exposure.
- **Belege:** Laufzeitprüfung der Rechte: `/root` `0700`, Secret-Dateien `0600 root:root`; betroffene Dateien unter anderem `app-core.env`, `ops.env`, `uptime-kuma.env`.
- **Risiko:** Bei Host-Root-Kompromittierung oder unvorsichtigem Debugging liegen zahlreiche App-Secrets sofort gesammelt vor.
- **Empfohlene Korrektur:** Secret-Handling mittelfristig auf einen klaren Betriebsprozess umstellen, etwa durch getrennte Secret-Dateien pro Dienst, minimierte Weitergabe an Container und dokumentierte Rotation.

### P3: Sicherheitsgrenze "nur über Tor" ist noch eher Zielbild als harte Durchsetzung
- **Befund:** Die Applikationen hören intern weiter auf klassischen TCP-Ports, und die Absicherung basiert derzeit primär auf Netzsegmenten und Docker-User-Chains statt auf einem konsequenten "nur onion ingress"-Modell.
- **Belege:** Exponierte Compose-Ports in `work/services/app-core/docker-compose.yml:36-163` und `work/services/ops/docker-compose.yml:12-120`; erfolgreiche direkte Erreichbarkeit der meisten Ports von `tor-edge` und `ops`.
- **Risiko:** Das Setup ist nicht direkt offen ins clearnet, aber intern noch deutlich breiter erreichbar als das gewünschte Sicherheitsmodell vermuten lässt.
- **Empfohlene Korrektur:** Tor als einziges Frontdoor-Prinzip technisch härter durchziehen und direkte TCP-Zugriffe zwischen den Segmenten auf explizite Ausnahmen reduzieren.

## Positive Befunde

- Der Host blockiert Management-Ports wie `8006` und `3128` gegenüber den internen Bridges per `nftables`.
- `rpcbind` ist auf dem Host nicht aktiv.
- `btc-node` ist im Vergleich zu den anderen CTs deutlich besser segmentiert; RPC ist auf `127.0.0.1` gebunden und die Input-Filter sind enger.
- Backup-Artefakte und Secret-Dateien haben aktuell restriktive Dateirechte.
- Die Staging-SQL-Datei unter `/root/homelab-staging/app-core/initdb/01-init.sql` enthält noch Platzhalter und keine ausgerollten Live-DB-Secrets.

## Empfohlene Reihenfolge für Korrekturen

1. Host-Monitoring und Host-Storage-Alerts ergänzen.
2. Ost-West-Firewalling pro Container ergänzen, insbesondere für `22` und `9100`.
3. Betreiberseitigen Alarmkanal wirklich durchtesten und Uptime-Kuma-Notifications definieren.
4. Bitcoin-Status klar als "noch nicht transaktionsbereit" dokumentieren und erst nach vollständigem Sync weiterhärten.
5. Backup-Ziel außerhalb des Hosts ergänzen.
6. Später Secrets und Admin-Identitäten aufräumen.

## Offene Annahmen

- Der Audit bewertet nur `ailab1` und die dort laufenden Container. Externe Geräte, echte Tor-Clients und Off-Host-Backup-Ziele wurden nicht einbezogen.
- Der Befund zu Host-SSH beschreibt die effektive Laufzeitkonfiguration. Eine Änderung daran wurde bewusst nicht vorgenommen, weil sie aktuell gegen die vorgegebene Zugangsregel laufen könnte.
