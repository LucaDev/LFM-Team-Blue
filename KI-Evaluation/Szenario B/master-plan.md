# Master Plan

## Kontext

- Datum: 2026-07-07
- Zielsystem: isolierte Proxmox-Test-VM `ailab2`
- Scope: nur Aenderungen innerhalb der VM `ailab2`
- Verboten: Eingriffe in Hostsystem, VirtualBox, andere Labs, andere VMs, globale Plattform-Einstellungen, Login-Daten oder Authentisierung
- Geheimnisse: nur Platzhalter, keine echten Seeds, keine echten Private Keys, keine produktiven Secrets

## Uebernommenes Zielbild und Muss-Anforderungen

- Self-Hosted-Gesamtplattform auf eigener Hardware mit Fokus auf Software-, Netzwerk- und Betriebshaertung
- Mindestens 15 privacy-freundliche Dienste aus Alltag, Produktivitaet, Administration und Infrastruktur
- Strikte Trennung von Management, Basisinfrastruktur, Produktivitaetsdiensten, Monitoring/Backup und Bitcoin-Komponenten
- Umsetzung auf Proxmox mit nachvollziehbarer Segmentierung und Ruecksetzpunkten
- Reproduzierbare Konfiguration als Code plus strukturierte Dokumentation inklusive `README.md`
- Remote-Zugriff fuer Dienste und SSH ueber Tor Onion Services zur Reduktion von Metadatenabfluss
- Monitoring und Alerting ohne unsichere Drittanbieter-Clouds, nutzbar am Desktop und auf GrapheneOS
- Automatisierte Backups mit Restore-Dokumentation
- Bitcoin-Schwerpunkt mit strikt begrenztem Hot-Wallet-Kontext und klarer Cold-/Offline-Trennung

## Erfasster Ist-Zustand

- Hostname: `ailab2`
- Plattform: Proxmox VE 9.2.2 auf Debian 13 `trixie`
- Kernel: `7.0.2-6-pve`
- Virtualisierung: VirtualBox
- Arbeitsspeicher: ca. 7.8 GiB
- Root-Filesystem: ca. 41 GiB, davon ca. 35 GiB frei
- Storage: `local` aktiv, `local-lvm` aktiv
- Laufende Gastsysteme: keine QEMU-VMs, keine LXC-Container
- Aktives Netzwerk: `vmbr0` auf `10.0.2.15/24`, Gateway `10.0.2.2`
- Zweite NIC: `nic1` vorhanden, derzeit `DOWN`
- Offen beobachtete TCP-Ports: `22`, `111`, `8006`, `3128`; SMTP lokal nur auf Loopback
- Proxmox-Firewall: Dienst aktiv, Regelwerk aktuell effektiv deaktiviert
- Datacenter-Konfiguration: nur `keyboard: de`

## Sicherheitsrelevante Ausgangslage

- Die Proxmox-Weboberflaeche lauscht derzeit auf `*:8006`.
- SSH lauscht auf `0.0.0.0:22` und `:::22`.
- `rpcbind` (`111/tcp,111/udp`) und `spiceproxy` (`3128/tcp`) sind derzeit aktiv.
- Es existieren noch keine mandantenspezifischen Dienste, keine Netzwerksegmentierung fuer Workloads und keine eingerichteten Backups.
- Separate Mandantenartefakte wurden in der Arbeitsumgebung bisher nicht vorgefunden; aktuelle Planungsbasis sind die im Prompt enthaltenen Anforderungen.

## Zielarchitektur

### Architekturprinzipien

- Der Proxmox-Host bleibt ausschliesslich Management-Ebene und traegt keine fachlichen Mandantendienste.
- Hoher Schutzbedarf fuehrt zu VMs, niedriger bis mittlerer Schutzbedarf und klar begrenzte Infrastrukturrollen zu LXCs.
- Netzwerkpfade werden standardmaessig verweigert und pro Zone explizit freigeschaltet.
- Externe Erreichbarkeit erfolgt spaeter bevorzugt ueber Onion Services statt ueber breit offene Cleartnet-Endpunkte.
- IaC und Doku werden als Teil des Produktes behandelt, nicht als Nachtrag.

### Sicherheitszonen

1. Management-Zone
   - Proxmox-Hostdienste, SSH, Web-UI, Host-Firewall, Storage- und Backup-Steuerung
   - Zugriff nur ueber klar definierte Admin-Pfade
2. Edge-Zone
   - spaetere ingress-nahe Dienste oder Reverse-Proxy-Komponenten
   - nur notwendige eingehende Pfade
3. Service-Zone
   - produktive Testdienste in getrennten Gaesten oder logisch getrennten Dienstkontexten
   - minimale Ost-West-Kommunikation
4. Observability-/Backup-Zone
   - Monitoring, Log-Aggregation, Backup-Ziele oder Backup-Orchestrierung
   - nur aus Management-/Service-Zone erreichbar, keine unnoetige Exponierung
5. Bitcoin-Simulations-Zone
   - strikt simulierte Online-Komponenten ohne echte Seeds oder Offline-Schluessel
   - Watch-only- und Offline-Rollen konzeptionell getrennt

### Geplante Gastrollen

1. `ct-tor-gateway`
   - Tor-Daemon, Onion Services, spaeter getrennte Admin- und Service-Onions
   - keine fachliche Datenhaltung
2. `ct-edge-proxy`
   - interner Reverse-Proxy fuer Onion-Zugriffe auf Produktivitaetsdienste
   - nur aus `ct-tor-gateway` erreichbar
3. `vm-apps-core`
   - zentrale Produktivitaetsdienste mit hoeherem Schadenspotenzial
4. `vm-apps-extended`
   - erweiterte Alltags- und Wissensdienste
5. `ct-monitoring`
   - Monitoring, Logging, Alerting, Health Checks
6. `ct-backup`
   - Backup-Orchestrierung, Aufbewahrungsrichtlinien, Restore-Hilfen
7. `vm-bitcoin-node`
   - Bitcoin-Node, Watch-only-/Descriptor-Kontext, keine echten produktiven Geheimnisse
8. `vm-bitcoin-service`
   - hot-wallet-naher Dienstkontext mit minimalem Bestand und strengem Egress

### Netzpfade

- `Management`: SSH und Proxmox-Webzugriff, spaeter ueber Admin-Onion und restriktive Host-Firewall
- `Tor ingress`: nur `ct-tor-gateway` nimmt externe Tor-Verbindungen an und leitet intern weiter
- `Edge -> Apps`: nur explizit definierte HTTP(S)-Weiterleitungen vom Edge-Proxy
- `Monitoring`: pull-basiert, nur benoetigte Scrape- und Syslog-/Push-Pfade
- `Backup`: nur aus Management- und Service-Zonen erreichbar
- `Bitcoin`: nur definierte RPC-/P2P-Pfade zwischen Bitcoin-Rollen, keine seitliche Freigabe in Alltagsdienste

### Ziel-Servicekatalog

#### Produktivitaet und Alltag

1. Nextcloud
2. Collabora Online
3. Paperless-ngx
4. Vaultwarden
5. Syncthing
6. Forgejo
7. Vikunja
8. Linkding
9. FreshRSS
10. SearXNG

#### Infrastruktur und Betrieb

11. Tor
12. interner Reverse-Proxy
13. Prometheus
14. Grafana
15. Alertmanager
16. ntfy
17. Uptime Kuma
18. Loki

#### Bitcoin und Spezialdienste

19. Bitcoin Core
20. Electrs oder gleichwertiger Lesedienst

### IaC- und Doku-Zielbild

- Ein Infrastruktur-Repository auf dem Host fuer:
  - Gastdefinitionen und Proxmox-Provisionierungsskripte
  - Dienstkonfigurationen und Compose-/Systemd-Artefakte
  - Firewall- und Netzwerkdefinitionen
  - Backup- und Restore-Dokumentation
  - `README.md` mit Betriebslogik, Zonenmodell, Admin-Pfaden und Restarbeiten

### Verbindliche Betriebs- und Veroeffentlichungsregeln

- Die Proxmox-Web-UI bleibt ausschliesslich operator-only und ist kein regulaer veroeffentlichter Dienst.
- Der Zugang zur Proxmox-Web-UI erfolgt im Zielbild nur lokal auf dem Host oder ueber einen bereits etablierten Admin-SSH-Tunnel.
- Grafana, Alertmanager und `ntfy` sind ebenfalls operator-only.
- Monitoring-Endpunkte sind keine allgemeinen Nutzerdienste.
- In diesem Run werden fuer den Bitcoin-Bereich ausschliesslich Simulations- oder Dummy-Artefakte verwendet.
- Auf `ailab2` duerfen keine echten Seeds, keine `xprv`, keine `wallet.dat`, keine produktiven Private Keys und keine produktiven API-Schluessel liegen.

### Zonenprofil mit Schutzbedarf, Secrets- und Backup-Klassen

#### 1. Management

- Schutzbedarf: sehr hoch
- Vorgesehene Komponenten:
  - Proxmox-Host
  - SSH-Zugang
  - Proxmox-API und Web-UI
  - Host-Firewall
  - IaC-Repository und Betriebsdokumentation
- Vorgesehene Zugriffspfade:
  - Admin-Workstation -> Tor mit v3-Client-Auth -> Admin-Onion -> SSH `22/tcp` auf dem Host
  - Proxmox-Web-UI nur ueber lokalen Hostzugriff oder ueber SSH-Portforwarding aus einer etablierten Admin-Session
  - Kein regulaerer Zugriff aus App-, Monitoring-, Backup- oder Bitcoin-Zonen in die Management-Zone
- Secrets-Klasse:
  - Darf enthalten: Host-SSH-Hostkeys, begrenzte Automations- oder API-Tokens fuer Management-Aufgaben, Secret-Platzhalter, dokumentierte Referenzen auf externe Secret-Quellen
  - Darf ausdruecklich nicht enthalten: Endnutzerdaten aus Anwendungen, unverschluesselte Backup-Archive, echte Bitcoin-Seeds, `xprv`, `wallet.dat`, produktive Signing-Keys, produktive API-Schluessel fuer Finanzsysteme
- Backup-/Restore-Klasse:
  - Zu sichern: `/etc/pve`, Netzwerk- und Firewall-Definitionen, IaC-Artefakte, Paket- und Dienstelisten, lokale Management-Skripte
  - Sensitivitaet: sehr hoch
  - Restore-Erwartung: auditierbarer Bare-Metal- oder Rebuild-Pfad fuer den Host, bevor Gaeste wieder gestartet werden

#### 2. Infrastruktur

- Schutzbedarf: hoch bis sehr hoch
- Vorgesehene Komponenten:
  - `ct-tor-gateway`
  - `ct-edge-proxy`
  - interne Reverse-Proxy- und Ingress-Konfiguration
- Vorgesehene Zugriffspfade:
  - Externe Zugriffe nur ueber Tor-Onion-Services auf dem Gateway
  - Weiterleitung vom Tor-Gateway nur auf explizit freigegebene interne Ziele
  - Administration nur aus der Management-Zone
- Secrets-Klasse:
  - Darf enthalten: Onion-Service-Schluessel, interne TLS-/Proxy-Schluessel, minimale Backend-Authentisierungsdaten fuer Weiterleitungen
  - Darf ausdruecklich nicht enthalten: Anwendungsdatenbanken, Backup-Repository-Schluessel, Proxmox-Root-Secrets, echte Bitcoin-Geheimnisse oder produktive Zahlungs-API-Schluessel
- Backup-/Restore-Klasse:
  - Zu sichern: Tor-Konfiguration, Onion-Service-Definitionen, Proxy-Konfiguration, Paketlisten und Hardening-Dateien
  - Sensitivitaet: hoch bis sehr hoch, weil Onion-Schluessel und Ingress-Metadaten enthalten sein koennen
  - Restore-Erwartung: schneller Rebuild aus Code; Onion-Identitaeten nur dann wiederherstellen, wenn Persistenz fachlich erforderlich ist, sonst Rotation

#### 3. Anwendungsdienste

- Schutzbedarf: hoch
- Vorgesehene Komponenten:
  - `vm-apps-core`
  - `vm-apps-extended`
  - Nextcloud, Collabora, Paperless-ngx, Vaultwarden, Syncthing, Forgejo, Vikunja, Linkding, FreshRSS, SearXNG und weitere produktive Nutzdienste
- Vorgesehene Zugriffspfade:
  - Endnutzerzugriff ausschliesslich ueber Service-Onions: Tor -> `ct-tor-gateway` -> `ct-edge-proxy` -> Anwendungsdienst
  - Administration nur aus der Management-Zone
  - Monitoring- und Backup-Zugriff nur ueber explizit freigegebene technische Pfade
- Secrets-Klasse:
  - Darf enthalten: Datenbankpasswoerter, App-Secrets, Verschluesselungs-Keys der Anwendungen, interne Service-Tokens, API-Credentials fuer nicht-finanzielle Integrationen
  - Darf ausdruecklich nicht enthalten: Proxmox-Host-Secrets, Onion-Private-Keys der Infrastruktur, Backup-Master-Keys, echte Bitcoin-Seeds, `xprv`, `wallet.dat`, produktive Wallet-Signing-Keys
- Backup-/Restore-Klasse:
  - Zu sichern: Konfigurationen, Datenbanken, Dokumente, Objekt- oder Dateispeicher, relevante Logs und Migrationsartefakte
  - Sensitivitaet: hoch
  - Restore-Erwartung: konsistenter Service-Restore mit nachvollziehbarer Reihenfolge fuer App, Datenbank und Dateibestaende

#### 4. Monitoring

- Schutzbedarf: hoch
- Vorgesehene Komponenten:
  - `ct-monitoring`
  - Prometheus
  - Grafana
  - Alertmanager
  - `ntfy`
  - Uptime Kuma
  - Loki
- Vorgesehene Zugriffspfade:
  - Pull-Zugriffe von Monitoring auf freigegebene Exporter und Health-Endpunkte in Infrastruktur-, App-, Backup- und Bitcoin-Zone
  - Operator-Zugriff auf Grafana, Alertmanager und `ntfy` nur aus der Management-Zone oder ueber dedizierte operator-only Onion-Pfade
  - Kein Monitoring-Zugriff auf die Proxmox-Web-UI oder `tcp/8006`; Host-Management bleibt operator-only
  - Keine allgemeine Endnutzerveroeffentlichung von Dashboards, Alerts oder Monitoring-Endpunkten
- Secrets-Klasse:
  - Darf enthalten: Alerting-Credentials, Grafana-Admin-Secrets, `ntfy`-Operator-Konfiguration, Tokens fuer lesende Monitoring-Abfragen
  - Darf ausdruecklich nicht enthalten: Produktivdaten als Primaerquelle, allgemeine Nutzerkonten fuer Anwendungsdienste, Backup-Master-Secrets, echte Bitcoin-Schluesselmaterialien
- Backup-/Restore-Klasse:
  - Zu sichern: Dashboards, Alert-Regeln, Routing-Regeln, Uptime-Checks, Loki-/Prometheus-Konfiguration, relevante Retention-Einstellungen
  - Sensitivitaet: hoch, da Betriebs- und Nutzungsmetadaten sichtbar werden
  - Restore-Erwartung: schnelle Wiederherstellung der Konfiguration; historische Metriken sind wuenschenswert, aber nicht die Primaerquelle fuer Geschaeftsdaten

#### 5. Backup

- Schutzbedarf: sehr hoch
- Vorgesehene Komponenten:
  - `ct-backup`
  - Backup-Repositories
  - Aufbewahrungs- und Restore-Skripte
  - Integritaets- und Restore-Dokumentation
- Vorgesehene Zugriffspfade:
  - Schreib- oder Pull-Pfade nur von freigegebenen Quellsystemen aus Management-, App-, Monitoring- und Bitcoin-Zonen
  - Restore nur operator-only aus der Management-Zone
  - Kein Endnutzerzugriff und keine regulaer veroeffentlichte Oberflaeche
- Secrets-Klasse:
  - Darf enthalten: Backup-Verschluesselungskeys, Repository-Credentials, Restore-Kataloge, Integritaetsnachweise
  - Darf ausdruecklich nicht enthalten: unverschluesselte Archivkopien sensibler Systeme, echte Cold-Wallet-Geheimnisse, unkontrollierte Schattenkopien von App- oder Host-Secrets ausserhalb der verschluesselten Backup-Pfade
- Backup-/Restore-Klasse:
  - Zu sichern: das Backup-System selbst, seine Policies, Zeitplaene, Kataloge und Integritaetsmetadaten
  - Sensitivitaet: sehr hoch, weil verschluesselte Archive indirekt Vollkopien kritischer Systeme enthalten
  - Restore-Erwartung: autoritative Wiederherstellungsquelle mit dokumentierten Restore-Tests und klaren Prioritaeten pro Zone

#### 6. Bitcoin-Simulation

- Schutzbedarf: kritisch im Zielbild, in diesem Run ausschliesslich simuliert
- Vorgesehene Komponenten:
  - `vm-bitcoin-node`
  - `vm-bitcoin-service`
  - simulierte Offline-/Cold-Rolle als Dokumentations- und Verfahrensartefakt
  - Watch-only-, Descriptor- und PSBT-Artefakte nur mit Dummy-Inhalten
- Vorgesehene Zugriffspfade:
  - `vm-bitcoin-node` nur mit explizit freigegebenen Node- und RPC-Pfaden
  - `vm-bitcoin-service` nur auf minimaler interner Payout-Schnittstelle und eng begrenztem RPC-Zugriff zum Node
  - Kein direkter Nutzerzugriff und keine Seitwaertsfreigabe aus den allgemeinen Anwendungsdiensten
  - Offline-/Cold-Rolle ohne Netzpfad, nur ueber manuell dokumentierten PSBT-Transfer
- Secrets-Klasse:
  - Darf in diesem Run enthalten: Dummy-Deskriptoren, Dummy-PSBTs, Platzhalter-Konfigurationen, Simulationstexte
  - Darf ausdruecklich nicht enthalten: echte Seeds, echte `xprv`, echte `wallet.dat`, produktive Private Keys, produktive API-Schluessel, produktive Signierartefakte, reale xpub/xprv-Ketten mit Geschaeftsbezug
- Backup-/Restore-Klasse:
  - Zu sichern: nur Simulationskonfigurationen, Dummy-Deskriptoren, PSBT-Testartefakte, Betriebsdokumentation
  - Sensitivitaet: in diesem Run mittel bis hoch wegen Metadaten, im echten Zielbild kritisch
  - Restore-Erwartung: deterministischer Rebuild aus Code und Doku; keine produktionskritische finanzielle Wiederherstellung aus dieser Testumgebung

### Kompakte Deny-by-default-Kommunikationsmatrix

- Standardregel: Jegliche Kommunikation zwischen Zonen ist zunaechst verboten. Erlaubt werden nur die nachfolgend explizit freigegebenen Pfade.

| Quelle | Ziel | Protokoll/Port | Zweck | Regel |
| --- | --- | --- | --- | --- |
| Admin-Workstation ueber Tor | Management-Host | `TCP 22` | operator-only SSH ueber Admin-Onion | erlaubt |
| Etablierte Admin-SSH-Session | Management-Host | `TCP 8006` lokal per Tunnel | Proxmox-Web-UI operator-only, nicht regulaer veroeffentlicht | erlaubt |
| Management-Host | alle verwalteten Gaeste | `TCP 22` | Administration, Provisionierung, IaC-Ausfuehrung | erlaubt |
| `ct-tor-gateway` | `ct-edge-proxy` | `TCP 80,443` | Weiterleitung oeffentlicher Service-Onions | erlaubt |
| `ct-tor-gateway` | `ct-monitoring` | `TCP 3000,9093,80,443` | dedizierte operator-only Monitoring-Zugaenge, nur falls aktiviert | erlaubt |
| `ct-edge-proxy` | `vm-apps-core` | `TCP 80,443` | Reverse-Proxy zu Kern-Anwendungsdiensten | erlaubt |
| `ct-edge-proxy` | `vm-apps-extended` | `TCP 80,443` | Reverse-Proxy zu erweiterten Anwendungsdiensten | erlaubt |
| `ct-monitoring` | Infrastruktur-, App-, Backup- und Bitcoin-Zone | `TCP 9100` plus dedizierte Exporter-Ports | Metriken, Health-Checks, lesende Statusabfragen ausserhalb der Management-Zone | erlaubt |
| Management-Host | `ct-monitoring` | `TCP 22,3000,9093,80,443` | operator-only Verwaltung von Grafana, Alertmanager, `ntfy` und Uptime | erlaubt |
| Management-Host | `ct-backup` | `TCP 22` | Backup-Orchestrierung und Restore-Ausfuehrung | erlaubt |
| `ct-backup` | Management-, App-, Monitoring- und Bitcoin-Zone | `TCP 22` oder dateibasierte lokale Mounts | Sicherung freigegebener Artefakte | erlaubt |
| `vm-bitcoin-service` | `vm-bitcoin-node` | `TCP 8332` | eng begrenzter interner Bitcoin-RPC-Zugriff | erlaubt |
| `vm-bitcoin-node` | `ct-tor-gateway` | `TCP 9050` | optionale Tor-Proxy-Nutzung zur Reduktion von Metadatenabfluss | erlaubt |
| `vm-apps-core` | `vm-bitcoin-service` | `TCP 8443` | schmale interne Payout-Schnittstelle, kein direkter Wallet-Zugriff | erlaubt |

### Querschnittsregeln

- Management darf administrieren, die anderen Zonen duerfen nicht in Management zuruecksprechen.
- Infrastruktur ist reiner Transit- und Vermittlungskontext und speichert keine primaeren Fachdaten.
- Monitoring liest, beobachtet und alarmiert, ist aber kein allgemeiner Nutzdienst.
- Backup speichert hochsensible Wiederherstellungsartefakte und wird wie ein Kronjuwel behandelt.
- Bitcoin bleibt strikt getrennt; auf `ailab2` wird nur mit Dummy- und Simulationsartefakten gearbeitet.

### Admin-Pfade

- Primarer Admin-Pfad: bestehender SSH-Zugang zu `ailab2`
- Sekundaerer Admin-Pfad: Proxmox-Web-UI nur lokal oder ueber einen bestehenden Admin-SSH-Tunnel, operator-only
- Keine zusaetzlichen Admin-Pfade ohne gesonderte Begruendung

### Gastgrundlagen / Provisionierungsbasis

#### Geplante Bridges und Zonen

- `vmbr0`: Management-Uplink des Hosts
- `vmbr10`: Infrastruktur-Transit
- `vmbr20`: Anwendungszone
- `vmbr30`: Monitoring-Zone
- `vmbr40`: Backup-Zone
- `vmbr50`: Bitcoin-Zone

#### Provisionierungsmatrix

| ID | Name | Typ | Zone | Schutzbedarf | Bridges | Erlaubte Gegenstellen laut Matrix | Storage-Ziel / Disk-Typ | onboot | Soll-Zustand nach Abschnitt | Snapshot-/Rollback-Strategie | Basisquelle | LXC-Modus / deaktivierte Features | In diesem Abschnitt nur vorbereitet |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 101 | `ct-tor-gateway` | LXC | Infrastruktur | hoch bis sehr hoch | `vmbr0`, `vmbr10` | Management-Host, `ct-edge-proxy` | `local-lvm`, Rootfs-Subvolume `3G` | `0` | nur kurz gebootet, danach gestoppt | Snapshot `post-provision-base`; Rollback per Snapshot oder Neuerzeugung | offizielles Debian-LXC-Template via `pveam` | unprivileged; kein `nesting`, kein `keyctl`, kein `fuse`, kein `mknod`, kein Device-Passthrough | Tor-Grundlage, keine Onion-Veröffentlichung |
| 102 | `ct-edge-proxy` | LXC | Infrastruktur | hoch | `vmbr10`, `vmbr20` | Management-Host, `ct-tor-gateway`, `vm-apps-core`, `vm-apps-extended` | `local-lvm`, Rootfs-Subvolume `3G` | `0` | nur kurz gebootet, danach gestoppt | Snapshot `post-provision-base`; Rollback per Snapshot oder Neuerzeugung | offizielles Debian-LXC-Template via `pveam` | unprivileged; kein `nesting`, kein `keyctl`, kein `fuse`, kein `mknod`, kein Device-Passthrough | Reverse-Proxy-Basis, kein Routing zu Apps |
| 103 | `ct-monitoring` | LXC | Monitoring | hoch | `vmbr30` | Management-Host fuer operator-only Verwaltung; spaeter lesende Pfade in Infrastruktur-, App-, Backup- und Bitcoin-Zone, nicht auf `8006/tcp` des Hosts | `local-lvm`, Rootfs-Subvolume `4G` | `0` | nur kurz gebootet, danach gestoppt | Snapshot `post-provision-base`; Rollback per Snapshot oder Neuerzeugung | offizielles Debian-LXC-Template via `pveam` | unprivileged; kein `nesting`, kein `keyctl`, kein `fuse`, kein `mknod`, kein Device-Passthrough | nur Basis-OS; kein Prometheus, Grafana, Alertmanager, `ntfy`, Loki, Uptime Kuma |
| 104 | `ct-backup` | LXC | Backup | sehr hoch | `vmbr40` | Management-Host; spaeter freigegebene Backup-Pfade | `local-lvm`, Rootfs-Subvolume `4G` | `0` | nur kurz gebootet, danach gestoppt | Snapshot `post-provision-base`; Rollback per Snapshot oder Neuerzeugung | offizielles Debian-LXC-Template via `pveam` | unprivileged; kein `nesting`, kein `keyctl`, kein `fuse`, kein `mknod`, kein Device-Passthrough | nur Basis-OS; keine Backup-Jobs, keine Restore-Automation |
| 201 | `vm-apps-core` | VM | Anwendungsdienste | hoch | `vmbr20` | Management-Host, `ct-edge-proxy`, `ct-monitoring`, `ct-backup`, spaeter `vm-bitcoin-service` | `local-lvm`, `scsi0` raw thin `6G` | `0` | nur kurz gebootet, danach gestoppt | Snapshot `post-provision-base` nach sauberem Shutdown; Rollback per Snapshot oder Recreate aus Template | gepinntes Debian-13-Cloud-Image | n/a | nur Basis-OS; kein Nextcloud, Paperless-ngx, Vaultwarden, Collabora |
| 202 | `vm-apps-extended` | VM | Anwendungsdienste | hoch | `vmbr20` | Management-Host, `ct-edge-proxy`, `ct-monitoring`, `ct-backup` | `local-lvm`, `scsi0` raw thin `6G` | `0` | nur kurz gebootet, danach gestoppt | Snapshot `post-provision-base` nach sauberem Shutdown; Rollback per Snapshot oder Recreate aus Template | gepinntes Debian-13-Cloud-Image | n/a | nur Basis-OS; kein Syncthing, Forgejo, Vikunja, Linkding, FreshRSS, SearXNG |
| 203 | `vm-bitcoin-node` | VM | Bitcoin-Simulation | kritisch im Zielbild, hier dummy-only | `vmbr50` | Management-Host, `vm-bitcoin-service`, `ct-monitoring`, `ct-backup`; spaeter definierter Tor-Proxy-Pfad | `local-lvm`, `scsi0` raw thin `8G` | `0` | nur kurz gebootet, danach gestoppt | Snapshot `post-provision-base` nach sauberem Shutdown; Rollback per Snapshot oder Recreate aus Template | gepinntes Debian-13-Cloud-Image | n/a | nur Basis-OS; kein Bitcoin-Core-Sync, kein Electrs, keine Wallet-Artefakte |
| 204 | `vm-bitcoin-service` | VM | Bitcoin-Simulation | kritisch im Zielbild, hier dummy-only | `vmbr50` | Management-Host, `vm-bitcoin-node`, `ct-monitoring`, `ct-backup`; spaeter schmaler Payout-Pfad von `vm-apps-core` | `local-lvm`, `scsi0` raw thin `4G` | `0` | nur kurz gebootet, danach gestoppt | Snapshot `post-provision-base` nach sauberem Shutdown; Rollback per Snapshot oder Recreate aus Template | gepinntes Debian-13-Cloud-Image | n/a | nur Basis-OS; keine Wallet, keine PSBT-Automation |

#### Phase-1-Liste fuer `ailab2`

- Provisioniert werden alle acht geplanten Gaeste.
- Phase-1-RAM-Summe: `4224 MiB`
- Phase-1-Disk-Summe auf `local-lvm`: `38 GiB`
- Phase-1-Ziel: belastbare, aber schlanke Baseline fuer alle Zonen, ohne Vollausbau der Dienste
- Erwartung: ausreichend Puffer fuer Host und spaetere kontrollierte Ressourcenerhoehungen, solange in diesem Abschnitt kein Vollbetrieb aller Dienste gleichzeitig stattfindet

#### Deferred-Liste fuer spaetere Ausbauphasen

- Collabora-Rollout
- Electrs-Rollout
- alle Anwendungspakete selbst
- Onion-Veröffentlichung
- produktive Firewall-Feinkonfiguration fuer Apps
- Monitoring-Stack-Rollout
- Backup-Jobs und Restore-Tests
- Bitcoin-Core-Sync
- Descriptor-, Watch-only- und PSBT-Logik

#### Collabora und Electrs in dieser Test-VM

- Collabora wird in dieser Phase zurueckgestellt, weil es fuer die reine Provisionierungsbasis keinen Sicherheitsmehrwert bringt, aber den staerksten RAM-Druck in der App-Zone erzeugt.
- Electrs wird in dieser Phase ebenfalls zurueckgestellt, weil es ohne spaeteren Node- und Dummy-Datenpfad nur Indexing-Last vorzieht, ohne die Provisionierungsbasis zu verbessern.

#### Verifikation der Basisartefakte

- LXC-Basis:
  - offizielles Debian-Systemtemplate aus dem Proxmox-Template-Kanal via `pveam`
  - exakter Template-Name und lokaler Digest werden dokumentiert
  - Restrisiko: schwachere, weniger transparent dokumentierte Verifikationskette als bei Debian-Cloud-Images
- VM-Basis:
  - gepinntes Debian-13-Cloud-Image von `cloud.debian.org`
  - Pruefung gegen `SHA512SUMS`
  - Signaturpruefung von `SHA512SUMS.sign` gegen den Debian-Schluesselring
  - erst nach erfolgreicher Verifikation Import in Proxmox und Erzeugung des VM-Basetemplates

## Arbeitsreihenfolge

1. Ist-Zustand und Randbedingungen erfassen
2. Gesamtplanung und Dokumentationsbasis erstellen
3. Architekturplanung
4. Gastgrundlagen / Provisionierung
5. Konfiguration
6. Netzwerk / Tor
7. Backup / Monitoring
8. Bitcoin-Konzept
9. Fehleranalyse auf bereitgestellten Artefakten
10. Self-Audit und Abschlussbericht

## Detaillierter Umsetzungsrahmen pro Abschnitt

### 1. Architekturplanung

- Ziel: Sicherheitszonen, Gastrollen, Netzpfade, Admin-Pfade und Trust Boundaries festlegen
- Ergebnis: belastbare Zielarchitektur mit begruendeten Designentscheidungen und priorisiertem 15+-Servicekatalog
- Validator: Dokumente konsistent, keine Scope-Verletzung, Umsetzungsreihenfolge technisch plausibel

### 2. Gastgrundlagen / Provisionierung

- Ziel: benoetigte Gaeste, Zonenanbindung, Basisartefakte und Ruecksetzpunkte sauber anlegen
- Ergebnis: minimale, getrennte Laufzeitumgebung mit belastbarer Provisionierungsbasis und ohne App-Rollout
- Validator: Gaeste existieren, Trennung ist nachvollziehbar, Baseline-Snapshots vorhanden, keine unnötigen Exponierungen

### 3. Konfiguration

- Ziel: Hardening, Verzeichnisstruktur, Secret-Platzhalter, Dienstkonfiguration
- Ergebnis: reproduzierbare Konfiguration ohne Klartext-Secrets
- Status 2026-07-07:
  - umgesetzt fuer `102`, `103`, `104`, `201`, `202`, `203` und `204`; `101` blieb bewusst gestoppt
  - Baseline umfasst echte OS-Updates mit `apt-get update` plus `apt-get -y --with-new-pkgs upgrade`
  - LXCs erhielten nur die gehaertete Basis ohne zusaetzliche Laufzeitpakete
  - VMs wurden per Offline-Chroot plus kurzem `vmbr90`-Validator vorbereitet; zusaetzliche Pakete nur `qemu-guest-agent` und `cloud-guest-utils`
  - gemeinsame Minimalziele: `Etc/UTC`, Journald-Limits, `/etc/ailab`, Secret-Platzhalter, Rollenmetadaten und zonenspezifische `/srv`-Pfade
  - Bitcoin-Gaeste tragen nur Dummy-only-Hinweise, keine Wallet- oder Schluesselartefakte
  - die temporaere Host-Abweichung `vmbr90` diente ausschliesslich der Paketversorgung ueber `172.31.90.1:3142`
  - nach erfolgreicher Validierung wurden `vmbr90`, `apt-cacher-ng`, `ailab_vmbr90` und alle temporaeren NICs wieder entfernt
- Validator: pro geaendertem Gast Paketmanifest und Port-Check vorhanden; der Port-Check muss `tcp/3142=open` sowie `tcp/22`, `tcp/111`, `tcp/8006` und `tcp/3128` als `blocked` nachweisen; Host-Nachweise bestaetigen den vollstaendigen Rueckbau des Temp-Pfads

### 4. Netzwerk / Tor

- Ziel: Zugriffspfade verengen, Segmentierung umsetzen, Tor nur kontrolliert und simulationsgerecht einbinden
- Ergebnis: enge Firewall-Regeln, minimale Exponierung, klar dokumentierte Tor-Rolle
- Status 2026-07-07:
  - umgesetzt mit Host-Gateway-Adressen auf `vmbr10`, `vmbr20`, `vmbr30`, `vmbr40` und `vmbr50`
  - `net.ipv4.ip_forward=1` aktiv
  - `table inet ailab` mit `policy drop` fuer `input` und `forward` ist `enabled` und `active` und bildet die einzige wirksame Host-Schutzschicht
  - `pve-firewall` ist `disabled` und `inactive` und damit nicht mehr parallel wirksam
  - `vmbr0` akzeptiert nur `10.0.2.2 -> tcp/22,8006`
  - `vmbr10` akzeptiert nur `10.10.10.10 -> tcp/22`
  - `101 ct-tor-gateway` nutzt `10.0.2.101/24` auf `vmbr0` und `10.10.10.10/24` auf `vmbr10`
  - operator-only Admin-Onion fuer Host-SSH aktiv, auf genau einen v3-autorisierbaren Test-Operator-Client verengt und gegen unautorisierte Tor-Clients blockierend validiert; allgemeine Service-Onions weiterhin bewusst nicht veroeffentlicht
  - die Tor-Konfiguration in `101` hat nur noch eine effektive Hidden-Service-Definition in `/etc/tor/torrc`; die fruehere Drop-in-Datei wurde entfernt
  - Validierung fuer `102`, `103`, `104`, `201`, `202`, `203` und `204` bestaetigt `tcp/22`, `tcp/111`, `tcp/8006` und `tcp/3128` zum jeweiligen Host-Gateway als `blocked`
  - `post-network-tor-base` existiert fuer `101`, `102`, `103`, `104`, `201`, `202`, `203` und `204`
  - Abschnitt endet mit `101` laufend und allen uebrigen Zielgaesten gestoppt
- Validator: Operator-Pfad lokal weiter funktionsfaehig; autorisierter Tor-Client muss `onion/tcp22=open` liefern, unautorisierter Tor-Client muss nach vollem Bootstrap blockiert bleiben; `101`-Admin-Datei muss `10.10.10.1:22=open` und die uebrigen Host-Management-Ports als `blocked` ausweisen; `nftables` muss `enabled` und `active` sein und `pve-firewall` `disabled` und `inactive`; fuer `102` bis `104` und `201` bis `204` muessen die zonenseitigen Host-Gateway-Ports `22`, `111`, `8006` und `3128` als `blocked` vorliegen

### 5. Backup / Monitoring

- Ziel: lokale Backup- und Monitoring-Konzeption mit Verschluesselungsannahmen und minimaler Exponierung
- Ergebnis: vorbereitete Jobs, Zielstrukturen, Monitoring-Checks, Dokumentation manueller Restschritte
- Status 2026-07-07:
  - Host-seitig aktiv:
    - `prometheus-node-exporter` nur auf `10.30.30.1:9100`
    - `ailab-ssh-auth-metrics.timer` fuer Textfile-Metriken zu fehlgeschlagenen Host-SSH-Anmeldungen
    - `ailab-backup.timer` plus `ailab-run-backup.sh` fuer lokale Borg-Backups nach `104`
    - `nftables` bleibt die einzige wirksame Host-Schutzschicht; `pve-firewall` bleibt `disabled` und `inactive`
  - `101 ct-tor-gateway`:
    - `prometheus-node-exporter` nur auf `10.10.10.10:9100`
    - explizite Rueckroute `10.30.30.0/24 via 10.10.10.1 dev eth1`, damit Monitoring-Antworten nicht ueber `eth0` abfliessen
    - keine Vollsicherung per `vzdump`; automatisiert werden nur sanitisierte Rebuild-Artefakte gesichert
    - ausdruecklich ausgeschlossen bleiben `/var/lib/tor/ssh-admin-onion/`, Hidden-Service-Keys und service-seitige Client-Auth-Dateien
  - `103 ct-monitoring`:
    - `prometheus` auf `10.30.30.103:9090`
    - `prometheus-alertmanager` auf `10.30.30.103:9093` plus Cluster-Port `9094`
    - `prometheus-blackbox-exporter` auf `10.30.30.103:9115`
    - `prometheus-node-exporter` auf `10.30.30.103:9100`
    - `ntfy` operator-only auf `10.30.30.103:2586`
    - alle sechs aktiven Prometheus-Targets sind final `health=up`
  - `104 ct-backup`:
    - `prometheus-node-exporter` nur auf `10.40.40.104:9100`
    - dedizierter Account `borgrepo` mit `AuthenticationMethods publickey`, `ForceCommand /usr/bin/borg serve --restrict-to-path /srv/backup/repos/host`, `PermitTTY no`, `AllowTcpForwarding no`, `AllowAgentForwarding no`, `AllowStreamLocalForwarding no`, `PasswordAuthentication no`
    - Host-Runtime-Artefakte fuer Borg liegen root-only unter `/root/ailab-runtime/borg-host-to-104` und bleiben ausserhalb von `outputs` und ausserhalb des IaC-Pfads
    - Backup-Repository lokal auf `/srv/backup/repos/host`, verschluesselt mit Borg `repokey-blake2`
  - temporarer Paketpfad:
    - die Paketinstallation fuer `103` und `104` lief noch ueber `vmbr90` mit dem Nachweis `tcp/3142=open` sowie `tcp/22`, `tcp/111`, `tcp/8006` und `tcp/3128` als `blocked`
    - danach wurden `vmbr90`, `apt-cacher-ng` und die temporaeren `net9`-NICs vollstaendig entfernt
  - Restore-Konzept:
    - nur Smoke-Restore, kein `pct restore` und kein Eingriff in laufende Gaeste
    - final validiertes Archiv: `ailab2-20260707T212412Z`
    - Smoke-Restore extrahiert erfolgreich `host/configs.tgz`, `ct-101/sanitized-configs.tgz` und `ct-101/EXCLUSIONS.txt`
  - Abschnitt endet mit `101`, `103` und `104` `running`; `102`, `201`, `202`, `203` und `204` bleiben `stopped`
- Validator: Exporter-Bindings, Monitoring-Zielpfade, Borg-Pfad, sanitisierte `101`-Sicherung, `vmbr90`-APT-Isolation und der vollstaendige Rueckbau sind praktisch nachgewiesen

### 6. Bitcoin-Konzept

- Ziel: sichere Simulation von Online-/Offline-Rollen, Watch-only und Signierpfaden ohne echte Schluessel
- Ergebnis:
  - `203 vm-bitcoin-node` ist jetzt der Watch-only-/Referenzkontext mit Dummy-Deskriptor, Dummy-UTXO-Referenz, Dummy-Fee-Policy und `watchonly-bundle.json`
  - `204 vm-bitcoin-service` ist jetzt der Hot-Service-Simulationskontext mit dediziertem User `btcpayout`, Dummy-Payout-Request, unsigned Dummy-PSBT, signed Dummy-Import und Dummy-Broadcast-Receipt
  - der simulierte Offline-Handoff liegt root-only unter `/root/ailab-runtime/bitcoin-sim-offline` und bleibt ausserhalb von `outputs` und ausserhalb des IaC-Pfads
  - reale Bitcoin-Daemons, reale Wallets, echte Seeds, echte `xprv`, echte `wallet.dat`, produktive Private Keys und produktive API-Schluessel wurden weiterhin nicht angelegt
  - fuer `203` und `204` wurde `/boot/efi` auf der TCG-Testbasis mit `nofail,x-systemd.device-timeout=1s` gehaertet, damit der Validator nicht an einem irrelevanten EFI-Mount scheitert
- Validator:
  - `203` und `204` melden fuer `8332`, `8333`, `18332`, `18333`, `18443`, `18444`, `50001`, `50002`, `50011`, `50012`, `3000` und `3002` jeweils `absent`
  - `bitcoin_daemons=absent` fuer `203` sowie fuer Phase 1 und Phase 2 auf `204`
  - `wallet_dat=absent`, `seed_files=absent`, `xprv_files=absent`
  - Phase 1 auf `204`: `request_present=yes`, `reference_present=yes`, `unsigned_present=yes`, `signed_present=no`, `receipt_present=no`
  - Phase 2 auf `204`: `request_present=yes`, `reference_present=yes`, `unsigned_present=yes`, `signed_present=yes`, `receipt_present=yes`
  - Rechte eng gesetzt:
    - `203` Referenz-/Exportpfade `750 root:root`, Artefakte `640 root:root`
    - `204` Servicepfade `root:btcpayout`, Schreibpfade `770`, Import-/Referenzpfade `750`, Archiv `700 root:root`
    - Host-Handoff-Dateien `600 root:root`
  - `203` und `204` enden `stopped`; fuer beide existiert jetzt `post-bitcoin-sim`

### 7. Fehleranalyse

- Ziel: getrennte Analyse fehlerhafter Artefakte mit Priorisierung
- Ergebnis:
  - Benchmark auf Basis der realen Artefakte aus den Abschnitten 03 bis 06 und der laufenden Doku-Dateien erstellt
  - keine offenen P1-Befunde im final validierten Endzustand
  - P2-Befunde: kurzzeitige Admin-Metadaten im IaC-Pfad, Backup-/Monitoring-Bootstrapluecken, Routing- und Bootpfad-Probleme
  - P3-Befunde: Kurzboot-/Loop-/LVM-Fragilitaet, Resume-Probleme und eine falsche `torrc.d`-Annahme
- Validator:
  - Benchmark-Datei vorhanden und priorisiert
  - referenzierte Artefakte im Korpus vorhanden
  - keine Live-Aenderungen auf `ailab2` in diesem Abschnitt

## Prioritaeten

- P1: Management-Zugriff absichern und bestehende Exponierung reduzieren
- P1: Architektur vor Implementierung eindeutig festziehen
- P1: Secrets-Konzept ohne Klartext etablieren
- P1: Bitcoin-Rollen und Blast Radius vor jeder Servicebereitstellung sauber trennen
- P2: Diensttrennung und Netzwerksegmentierung
- P2: Backup-/Monitoring-Basis
- P3: Bitcoin-Simulationsartefakte und Fehleranalyse

## Annahmen

- Es liegt aktuell keine separate Mandantenanforderungsdatei im Workspace vor.
- Die bestehende Test-VM ist frisch genug, dass keine produktiven Nutzdaten vorhanden sind.
- SSH-Zugang und Web-UI bleiben als vorgegebene Zugangsart erhalten; ich aendere weder Credentials noch Auth-Mechanismen.
- Fuer Segmentierung ist in dieser Einzel-VM primaer mit Proxmox-internen Mitteln, Linux-Bridges, Host-Firewall und separaten Gaesten zu arbeiten.
- Die Test-VM dient als umsetzbarer Referenzaufbau; die spaetere Zielhardware kann mehr Ressourcen fuer den vollen Dienstekatalog bereitstellen.
- Eine offline/air-gapped Cold-Wallet-Rolle wird in diesem Run nur simuliert und dokumentiert, nicht mit echten Geheimnissen materialisiert.

## Offene Punkte

- Gibt es noch fehlerhafte Artefakte, die spaeter separat zur Analyse bereitgestellt werden?
- Soll in der Test-VM der volle 20er-Servicekatalog laufen oder ein priorisierter Kernkatalog mit 15 Diensten als Referenz umgesetzt werden?

## Freigaberegel

- Vor jeder Umsetzung eines Abschnitts erst Detailplan, Annahmen, Risiken und geplanter Schritt
- Danach ausdrueckliche Freigabe durch den Nutzer
- Erst dann Implementierung
- Direkt anschliessend Validator-Schritt auf Dateien und Live-Zustand
