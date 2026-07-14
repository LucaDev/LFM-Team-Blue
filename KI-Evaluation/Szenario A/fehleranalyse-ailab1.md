# Fehleranalyse `ailab1`

## Scope

- Datum: `2026-07-06`
- Ziel: abschließende Analyse von Host, Containern, Netzwerk, Tor, Backup, Monitoring und Bitcoin
- Modus: nur Prüfung und Dokumentation, keine Korrekturen in diesem Abschnitt

## Kurzfazit

- Es gibt aktuell keinen akuten Dienstausfall: Prometheus sieht `21` aktive Targets ohne `down`, es gibt keine `firing` Alerts, und `bitcoind` läuft stabil im Initial Block Download.
- Die relevanten Restprobleme sind überwiegend strukturell: Management-Exposure des Proxmox-Hosts, fehlende echte Alert-Zustellung, Backup-Lücken für Tor-Identitäten und Bitcoin sowie eine noch offene Registrierung bei Vaultwarden.

## Update nach Behebung

- Befund `1` ist behoben:
  - `201`, `202`, `203` und `204` sind jetzt von `10.10.10.1` und `10.10.20.1` auf `22`, `8006`, `3128` und `111` blockiert.
  - `rpcbind.service` und `rpcbind.socket` sind deaktiviert und inaktiv.
- Befund `2` ist lokal behoben:
  - `203 ops` enthält jetzt zusätzlich `ntfy` und `alert-forwarder`.
  - Alertmanager routet auf den lokalen Webhook-Forwarder.
  - Es gibt eine eigene Alerts-Onion mit `HTTP 200`.
  - Die Forwarder-Logs zeigen wiederholt erfolgreiche `POST /alertmanager`-Annahmen mit `204`.
  - Restoffen bleibt nur bewusst, dass kein externer Mail-, Chat- oder Push-Receiver außerhalb des Labors konfiguriert wurde.
- Befund `3` ist wesentlich reduziert:
  - der Backup-Job exportiert jetzt zusätzlich `tor-edge`-Identitäten und `btc-node`-Konfiguration inklusive Onion-/Wallet-Artefakten, falls vorhanden.
  - ein manueller Post-Remediation-Lauf unter `/var/lib/homelab-backups/runs/20260706-224115` wurde gestartet, hat bereits den Snapshot für `202` erzeugt und läuft weiter für `203`.
  - offenes Betriebsrisiko bleibt die vom Host gemeldete Thin-Pool-Knappheit bei Snapshot-Backups.
- Befund `4` ist behoben:
  - `Vaultwarden` läuft jetzt mit `SIGNUPS_ALLOWED=false` und `INVITATIONS_ALLOWED=true`.
  - der Bootstrap-Hinweis über den vorhandenen `ADMIN_TOKEN` wurde in die Secrets-Dokumentation aufgenommen.
- Befund `5` ist teilweise behoben:
  - `homelab-backup.service` wurde nach der Korrektur bewusst gestartet und arbeitet.
  - ein vollständiger Restore-Drill bleibt weiter offen.

## Zusatzbefund aus der Behebung

- Während der Remediation fiel der bereitgestellte Managementzugriff nach einem reinen Gast-Reboot vorübergehend aus, obwohl `sshd` und `pveproxy` im Gast sauber liefen.
- Paketmitschnitte im Gast zeigten:
  - TCP-Handshake und Server-Banner gingen durch,
  - der Client sendete über den festhängenden VirtualBox-Portforward-Pfad danach jedoch keine verwertbare SSH-Nutzlast mehr in den Gast.
- Erst ein vollständiger Neustart des VirtualBox-Prozesses für genau diese VM stellte `SSH :2224` und `https://127.0.0.1:8011` wieder her.
- Bewertung:
  - Das war ein Problem der äußeren Nested-VirtualBox-NAT/Portforward-Schicht, nicht der nun laufenden Gastkonfiguration selbst.

## Befunde

### 1. Hoch: Die Proxmox-Management-Ebene ist aus allen Service-Containern direkt erreichbar

- Laufzeitprüfung: `201`, `202`, `203` und `204` konnten die Host-IP-Adressen `10.10.10.1` und `10.10.20.1` jeweils auf `22`, `8006`, `3128` und `111` erreichen.
- Host-Laufzeitprüfung: `nft` hat aktuell keine eingehenden Filterregeln auf dem Host, und `rpcbind` ist auf `0.0.0.0:111` sowie `[::]:111` aktiv.
- Risiko: Ein kompromittierter Dienstcontainer hat damit einen direkten Pfad zur Proxmox-Verwaltung und zu zusätzlichen Host-Diensten. Das schwächt die beabsichtigte Trennung zwischen Management-Plane und Service-Netzen deutlich.
- Sichere Abhilfe: Host-Firewall auf `ailab1` so einschränken, dass `22`, `8006` und `3128` nur über die gewünschte Management-Seite erreichbar sind; unnötige Host-Dienste wie `rpcbind` deaktivieren, wenn sie nicht gebraucht werden.

### 2. Hoch: Es gibt Monitoring, aber keine echte Alert-Zustellung

- Alertmanager ist nur auf einen leeren Empfänger `local-ui` geroutet; es ist keine Mail-, Webhook-, Push- oder Chat-Zustellung definiert. Siehe [alertmanager.yml](C:/Users/AK/Documents/Codex/2026-07-06/du-arbeitest-auf-einer-vorbereiteten-isolierten-2/work/services/ops/config/alertmanager/alertmanager.yml:2).
- Laufzeitprüfung: Uptime Kuma hat `15` Monitore, aber `0` Notifications.
- Risiko: Ausfälle werden zwar intern erkannt, aber nicht aktiv an den Nutzer zugestellt. Im Alltag bedeutet das: Man sieht Probleme nur, wenn man das Dashboard selbst aufruft.
- Sichere Abhilfe: Einen expliziten Alarmweg festlegen, zum Beispiel Mail, `ntfy`, Matrix oder Signal über Tor oder lokal vertrauenswürdige Infrastruktur, und diesen in Alertmanager und/oder Uptime Kuma konfigurieren.

### 3. Mittel: Die Backup-Strategie deckt die Tor- und Bitcoin-Kontinuität nicht ausreichend ab

- Der automatisierte Backup-Job sichert nur `202` und `203`. Siehe [homelab-backup.sh](C:/Users/AK/Documents/Codex/2026-07-06/du-arbeitest-auf-einer-vorbereiteten-isolierten-2/work/scripts/homelab-backup.sh:35) und [homelab-backup.sh](C:/Users/AK/Documents/Codex/2026-07-06/du-arbeitest-auf-einer-vorbereiteten-isolierten-2/work/scripts/homelab-backup.sh:37).
- `201 tor-edge` wird bewusst nur config-basiert gesichert, ausdrücklich ohne Hidden-Service-Private-Keys. Siehe [homelab-backup.sh](C:/Users/AK/Documents/Codex/2026-07-06/du-arbeitest-auf-einer-vorbereiteten-isolierten-2/work/scripts/homelab-backup.sh:55).
- `204 btc-node` ist im Backup-Job gar nicht enthalten.
- Risiko: Nach einem Restore würden sich die Onion-Adressen ändern, weil die Tor-Identitäten fehlen. Der Bitcoin-Knoten müsste ohne vorbereiteten Recovery-Pfad neu aufgebaut oder neu synchronisiert werden.
- Sichere Abhilfe: Einen separaten, stark geschützten Exportpfad für die Hidden-Service-Schlüssel definieren und mindestens Konfiguration plus Wiederanlaufpfad für `204` sichern oder sehr klar dokumentieren.

### 4. Mittel: Vaultwarden erlaubt weiterhin Selbstregistrierung auf der veröffentlichten Onion-Adresse

- Die Compose-Definition setzt `SIGNUPS_ALLOWED: "true"`. Siehe [docker-compose.yml](C:/Users/AK/Documents/Codex/2026-07-06/du-arbeitest-auf-einer-vorbereiteten-isolierten-2/work/services/app-core/docker-compose.yml:54).
- Die Laufzeitprüfung bestätigt `SIGNUPS_ALLOWED=true` im laufenden Container.
- Risiko: Sobald die Onion-Adresse weitergegeben oder anderweitig bekannt wird, können ungewollte Konten angelegt werden.
- Sichere Abhilfe: Erst den gewünschten Erstnutzer sauber anlegen, danach Registrierungen deaktivieren und nur noch kontrollierte Einladungen oder Admin-Anlage zulassen.

### 5. Niedrig: Der zeitgesteuerte Backup-Pfad ist aktiviert, aber noch nicht durch einen echten Timer-Lauf bewiesen

- Laufzeitprüfung: `homelab-backup.timer` ist aktiv, aber `homelab-backup.service` hat noch keine durch den Timer erzeugten Journal-Einträge; der nächste Lauf steht erst für `2026-07-07 03:28:20 CEST` an.
- Risiko: Die manuelle Backup-Variante wurde validiert, der tatsächliche Nachtlauf über `systemd` aber noch nicht.
- Sichere Abhilfe: Nach den Sicherheitskorrekturen den nächsten Timer-Lauf gezielt abwarten oder den Service einmal bewusst über `systemctl start homelab-backup.service` prüfen.

## Positiv verifiziert

- Der Host kommt trotz der Änderungen stabil hoch; alle vier Container laufen.
- Die Container-Firewalls blockieren den Host aktuell korrekt von den direkten App-, Ops- und Bitcoin-Dienstports.
- `bitcoind` läuft mit `onlynet=onion`, `dnsseed=0`, lokaler RPC-Bindung und publizierter Onion-P2P-Adresse.
- Prometheus sieht aktuell keine ausgefallenen Targets und keine aktiven Alerts.

## Empfohlene Reihenfolge für Korrekturen

1. Management-Exposure des Hosts schließen.
2. Einen echten Alarmkanal definieren und einrichten.
3. Backup- und Restore-Konzept für Onion-Identitäten und `btc-node` vervollständigen.
4. Vaultwarden-Signups nach Erstbenutzeranlage deaktivieren.
5. Den geplanten Backup-Timerlauf einmal end-to-end verifizieren.
