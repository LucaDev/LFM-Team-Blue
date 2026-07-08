# Decision Log

## D-001 Dokumentation zuerst

- Anforderung: Zuerst Ist-Zustand erfassen, dann planen, dann umsetzen.
- Gewaehlte Loesung: Vor jeder technischen Aenderung werden Planungs- und Nachweisdateien erstellt und laufend gepflegt.
- Sicherheitsbegruendung: Das reduziert Fehlgriffe auf der VM und schafft eine nachvollziehbare Freigabekette.
- Verworfene Alternative: Sofortige Hardening-Aenderungen direkt auf dem Host ohne Dokumentationsbasis.
- Offenes Restrisiko: Dokumentation kann Annahmen enthalten, solange noch keine detailierten Mandantenartefakte vorliegen.

## D-002 Scope strikt auf `ailab2`

- Anforderung: Keine Eingriffe ausserhalb der zugewiesenen VM.
- Gewaehlte Loesung: Alle geplanten Massnahmen werden ausschliesslich innerhalb von `ailab2` umgesetzt; Host-, VirtualBox- oder globale Plattformaenderungen bleiben ausgeschlossen.
- Sicherheitsbegruendung: Das verhindert Seiteneffekte ausserhalb des Testlabors.
- Verworfene Alternative: Netzwerk- oder Portweiterleitungsanpassungen auf Host- oder Hypervisor-Ebene.
- Offenes Restrisiko: Einige Exponierungen koennen dadurch nur innerhalb der VM eingeschraenkt, aber nicht auf Host-Ebene entfernt werden.

## D-003 Logische Sicherheitszonen in einer Einzel-VM

- Anforderung: Netzwerksegmentierung und enge Zugriffspfade bevorzugen.
- Gewaehlte Loesung: Sicherheitszonen werden zunaechst logisch innerhalb von Proxmox geplant und spaeter ueber getrennte Gaeste, Bridges, Firewall-Regeln und minimale Admin-Pfade umgesetzt.
- Sicherheitsbegruendung: Das ist innerhalb des erlaubten Scopes realistisch und reduziert Vertrauensdurchgriff zwischen Rollen.
- Verworfene Alternative: Externe physische oder hostweite Segmentierung.
- Offenes Restrisiko: In einer Einzel-VM bleibt ein gemeinsamer Host-Kernel eine harte Vertrauensgrenze.

## D-004 Secrets nur als Platzhalter

- Anforderung: Keine Klartext-Secrets, keine echten Seeds, keine echten Private Keys.
- Gewaehlte Loesung: Saemtliche spaeteren Konfigurationen verwenden Platzhalter, Secret-Dateien ausserhalb der Doku oder dokumentierte manuelle Restschritte.
- Sicherheitsbegruendung: So entsteht keine versehentliche Offenlegung ueber Doku, Compose-Dateien oder Shell-History.
- Verworfene Alternative: Demo-Secrets direkt in Konfigurationsdateien oder Markdown.
- Offenes Restrisiko: Manuelle Nachpflege echter Secrets bleibt spaeter notwendig und muss diszipliniert erfolgen.

## D-005 Keine Authentisierungs- oder Credential-Aenderungen

- Anforderung: Login-Daten und Authentisierung nicht aendern, sofern nicht explizit gefordert.
- Gewaehlte Loesung: Sicherheitsmassnahmen werden ueber Netzwerkpfade, Rollen, Firewalls und Dienstkonfiguration umgesetzt, nicht ueber Credential-Wechsel.
- Sicherheitsbegruendung: Das respektiert den Scope und vermeidet ungewollte Zugriffsausfaelle.
- Verworfene Alternative: Passwortwechsel, SSH-Hardening mit neuer Schluesselpflicht oder globale Auth-Aenderungen.
- Offenes Restrisiko: Bestehende Zugangsdaten bleiben unveraendert und muessen deshalb ueber zusaetzliche Zugriffsbeschraenkungen kompensiert werden.

## D-006 Gemischtes Isolationsmodell

- Anforderung: Strikte Isolation und Netztrennung auf Proxmox.
- Gewaehlte Loesung: Hoher Schutzbedarf und Bitcoin-Rollen werden in VMs geplant; leichtere Infrastrukturrollen wie Tor-Gateway, Monitoring und Backup bevorzugt in LXCs.
- Sicherheitsbegruendung: Das begrenzt Seiteneffekte bei Kompromittierung, ohne die Testressourcen durchgehend mit Voll-VMs zu ueberlasten.
- Verworfene Alternative: Alles in einem Host oder alles in einem grossen Docker-Stack.
- Offenes Restrisiko: LXC-Isolation ist schwacher als eine vollstaendige VM-Trennung.

## D-007 Tor-First fuer Remote-Zugriff

- Anforderung: Remote-Zugriff auf Dienste und SSH ueber Tor Onion Services.
- Gewaehlte Loesung: Ein dedizierter Tor-Gateway-Kontext stellt getrennte Onion Services fuer Admin- und Nutzpfade bereit.
- Sicherheitsbegruendung: Das reduziert direkte Exponierung und begrenzt Metadatenabfluss ueber clearnet-seitige Inbound-Pfade.
- Verworfene Alternative: Direkte Exponierung aller Dienste ueber clearnet oder ein klassisches VPN als alleiniger Fernzugang.
- Offenes Restrisiko: Tor wird zu einem kritischen Betriebsbestandteil und kann Performance- oder Erreichbarkeitsgrenzen einfuehren.

## D-008 Bitcoin mit kleinem Hot-Kontext und PSBT-Trennung

- Anforderung: Automatisierte Bitcoin-Transaktionen bei gleichzeitiger Trennung von Hot- und Cold-Vermoegen.
- Gewaehlte Loesung: Online nur minimaler Hot-Wallet-Kontext; Cold-Rolle bleibt air-gapped und wird ueber Watch-only-, Descriptor- und PSBT-Prozesse logisch angebunden.
- Sicherheitsbegruendung: Ein kompromittierter Server soll nur einen eng begrenzten Wallet-Bestand und keine Cold-Schluessel gefaehrden.
- Verworfene Alternative: Monolithische Hot-Wallet auf dem Server fuer den gesamten Bestand.
- Offenes Restrisiko: Der online benoetigte Hot-Wallet-Anteil bleibt prinzipiell verlustgefaehrdet.

## D-009 Monitoring und Alarmierung ohne Drittanbieter-Cloud

- Anforderung: Desktop- und GrapheneOS-taugliches Monitoring und Alerting ohne unsichere Cloud-Dienste.
- Gewaehlte Loesung: Self-hosted Monitoring-Stack mit lokaler Alarmierung ueber eigene Kanaele und onion-erreichbare Oberflaechen.
- Sicherheitsbegruendung: So verbleiben Alarmierungsdaten im eigenen Vertrauensbereich.
- Verworfene Alternative: SaaS-Monitoring oder Push-Dienste externer Anbieter.
- Offenes Restrisiko: Mobile Zustellung muss gegen Verfuegbarkeit, Batterieverbrauch und Bedienbarkeit abgewogen werden.

## D-010 Operator-only fuer Management- und Monitoring-Oberflaechen

- Anforderung: Administrative Oberflaechen duerfen nicht unnoetig exponiert werden.
- Gewaehlte Loesung: Proxmox-Web-UI, Grafana, Alertmanager und `ntfy` werden als operator-only definiert; Monitoring-Endpunkte sind keine allgemeinen Nutzerdienste.
- Sicherheitsbegruendung: Das reduziert die Angriffsoberflaeche und verhindert, dass Betriebsdaten versehentlich als Nutzdienst veroeffentlicht werden.
- Verworfene Alternative: dieselben Oberflaechen als regulare Multiuser-Webdienste mit breiter Erreichbarkeit.
- Offenes Restrisiko: Operator-only-Dienste enthalten weiterhin hochsensible Metadaten und bleiben bei Fehlkonfiguration angreifbar.

## D-011 Secrets- und Backup-Klassen pro Zone

- Anforderung: Secrets und Wiederherstellungsartefakte muessen pro Bereich klar begrenzt sein.
- Gewaehlte Loesung: Jede Zone erhaelt eine explizite Secrets-Klasse und eine Backup-/Restore-Klasse mit erlaubten und verbotenen Artefakten.
- Sicherheitsbegruendung: So wird Secret-Sprawl reduziert und Restore-Verantwortung pro Zone klar abgegrenzt.
- Verworfene Alternative: Einheitliche, unspezifische Secret- und Backup-Behandlung fuer alle Rollen.
- Offenes Restrisiko: Verschluesselte Backups koennen indirekt sehr viele sensible Artefakte enthalten und bleiben deshalb Kronjuwelen.

## D-012 Bitcoin-Dummy-only auf `ailab2`

- Anforderung: Bitcoin nur als sichere Simulation, ohne echte Seeds oder produktive Geheimnisse.
- Gewaehlte Loesung: Auf `ailab2` sind nur Dummy-Deskriptoren, Dummy-PSBTs und Platzhalterkonfigurationen erlaubt; echte Seeds, `xprv`, `wallet.dat`, produktive Private Keys und produktive API-Schluessel sind verboten.
- Sicherheitsbegruendung: Das verhindert, dass die Testumgebung versehentlich zu einem echten Wallet- oder Signiersystem wird.
- Verworfene Alternative: Teilweise Nutzung echter Wallet-Artefakte fuer realistischere Tests.
- Offenes Restrisiko: Auch Dummy-Artefakte koennen Architektur- und Metadaten verraten und muessen sauber getrennt bleiben.

## D-013 Storage- und Template-Trennung fuer Provisionierung

- Anforderung: Saubere technische Provisionierungsbasis mit nachvollziehbarer Herkunft der Gastartefakte.
- Gewaehlte Loesung: `local` dient nur als Staging fuer Templates und Images; `local-lvm` enthaelt ausschliesslich die Guest-Rootfs und VM-Disks. VMs basieren auf verifizierten Debian-Cloud-Images, LXCs auf offiziellen Debian-Templates aus dem Proxmox-Kanal.
- Sicherheitsbegruendung: Das trennt Download-Artefakte von Laufzeitdaten und reduziert Fehlgriffe bei Guest-Storage und Rollback.
- Verworfene Alternative: Mischbetrieb von Templates, Images und Guest-Disks auf demselben Directory-Storage.
- Offenes Restrisiko: Die Vertrauenskette fuer LXC-Templates ist weniger explizit dokumentiert als die Signaturpruefung der Debian-Cloud-Images.

## D-014 Phase-1 bewusst schlank

- Anforderung: Provisionierungsbasis soll die Zielzonen abbilden, ohne `ailab2` unnoetig zu ueberfrachten.
- Gewaehlte Loesung: Alle acht geplanten Gaeste werden in einer schlanken Phase-1-Ressourcenklasse provisioniert, bleiben mit `onboot=0` und enden nach Baseline-Tests im Zustand `stopped`.
- Sicherheitsbegruendung: Das reduziert Angriffsoberflaeche und Ressourcenlast, solange Konfiguration, Netzwerk, Backup und Monitoring noch nicht fertiggestellt sind.
- Verworfene Alternative: Vollausbau der Dienste und dauerhaft laufende Gaeste bereits im Provisionierungsabschnitt.
- Offenes Restrisiko: Spaeterer Vollbetrieb wird Re-Sizing fuer einzelne Zonen erfordern.

## D-015 Lokale VM-Ausweichstrategie ohne Nested KVM

- Anforderung: Geplante VMs sollen in der isolierten Test-VM validiert werden, ohne Host- oder VirtualBox-Aenderungen.
- Gewaehlte Loesung: Da auf `ailab2` kein nutzbares Nested-KVM bereitsteht, wurden die vier QEMU-Gaeste fuer diesen Referenzaufbau mit `kvm=0` per Softwareemulation kurz gebootet und danach wieder gestoppt.
- Sicherheitsbegruendung: Das bleibt strikt im Scope von `ailab2` und vermeidet Eingriffe in Hostsystem oder Hypervisor-Konfiguration.
- Verworfene Alternative: Aktivierung von Nested Virtualization ausserhalb der Test-VM oder Umstellung der Bitcoin-/App-Rollen auf Container.
- Offenes Restrisiko: Die Validierung deckt Startfaehigkeit und Provisionierungszustand ab, aber nicht die spaetere Performance eines echten KVM-Betriebs.

## D-016 Temporaere Paketversorgung nur ueber `vmbr90`

- Anforderung: Die internen Gaeste `102`, `103`, `104`, `201`, `202`, `203` und `204` brauchen fuer den Konfigurationsabschnitt Paketversorgung, obwohl ihre Zielzonen keinen regulaeren Uplink und keine Host-IP auf den internen Bridges erhalten sollen.
- Gewaehlte Loesung: Fuer Abschnitt 03 wird temporaer nur `vmbr90` mit `172.31.90.1/24` angelegt. Darauf lauscht ausschliesslich ein host-lokales `apt-cacher-ng` auf `172.31.90.1:3142`; eine gesonderte `nftables`-Tabelle erlaubt von `vmbr90` nur diesen Port und verwirft sonst Host-Input und Forwarding.
- Sicherheitsbegruendung: So bleibt die Paketversorgung lokal auf `ailab2`, ohne den Zonen einen regulaeren Internet-Uplink oder einen zweiten Management-Pfad zu geben.
- Verworfene Alternative: temporaerer NAT/Uplink fuer jede Zone oder zweite NICs mit generischem Internetzugang.
- Offenes Restrisiko: Der Abschnitt verlaesst sich auf korrekten Rueckbau des temporaren Host-Pfads; ein Fehlcleanup wuerde die Temp-Exponierung verlaengern.

## D-017 Baseline umfasst echte Sicherheitsupdates

- Anforderung: Vor der Umsetzung musste klar festgelegt werden, ob nur `apt update` oder auch echte Sicherheitsupdates Teil der Baseline sind.
- Gewaehlte Loesung: Alle geaenderten Gaeste erhalten `apt-get update` plus `apt-get -y --with-new-pkgs upgrade`; zusaetzliche Pakete bleiben auf das Minimum begrenzt.
- Sicherheitsbegruendung: Dadurch startet die weitere Architektur nicht auf absichtlich ungepatchten Gastbasen, obwohl App-Runtimes noch gar nicht ausgerollt werden.
- Verworfene Alternative: nur Paketindex aktualisieren und bekannte Basisluecken bis spaeter offen lassen.
- Offenes Restrisiko: Die Updates sind nur eine Punkt-in-Zeit-Baseline; spaetere Servicepakete und neue CVEs erfordern weiterhin laufende Patch-Disziplin.

## D-018 VM-Konfiguration per Offline-Chroot plus Kurzboot

- Anforderung: Die VM-Basis fuer `201` bis `204` musste in der Testumgebung reproduzierbar konfiguriert werden, ohne Scope-Ausweitung und trotz `kvm=0`.
- Gewaehlte Loesung: Die eigentliche Basiskonfiguration der VMs erfolgt offline per Chroot direkt auf den VM-Disks; danach booten die Gaeste nur kurz fuer den `vmbr90`-Validator und fahren wieder herunter.
- Sicherheitsbegruendung: Das begrenzt die Zeit mit temporaerer Zusatz-NIC, reduziert Abhaengigkeit von instabilen Erstboot-Pfaden und haelt die Validierung auf den benoetigten Minimalumfang begrenzt.
- Verworfene Alternative: laengerer Online-Provisionierungspfad nur ueber Cloud-Init, QGA und laufende VMs in Softwareemulation.
- Offenes Restrisiko: Boot-Timing und Gasterlebnis unter TCG koennen von spaeterem echtem KVM-Betrieb abweichen.

## D-019 IaC-Pfad ohne echte Secrets, aber mit Gastmanifesten

- Anforderung: Das IaC-Repo darf keine echten Secrets enthalten; pro Gast soll ein Paket- und Versionsmanifest nachvollziehbar geloggt werden.
- Gewaehlte Loesung: Unter `/root/ailab2-iac` werden nur Doku, Platzhalter, Skripte, Portchecks und Paketmanifeste gespeichert. Echte Secrets, Seeds, `xprv`, `wallet.dat`, produktive Private Keys und produktive API-Schluessel bleiben verboten.
- Sicherheitsbegruendung: Das schafft Reproduzierbarkeit und Auditierbarkeit, ohne die Hilfsartefakte selbst zu einem Secret-Container zu machen.
- Verworfene Alternative: ad-hoc Shell-History, unstrukturierte Einzelnotizen oder secrettragende `.env`-/Compose-Dateien im IaC-Pfad.
- Offenes Restrisiko: Paketmanifeste und Rollenmetadaten verraten interne Inventar- und Versionsinformationen und muessen deshalb spaeter ebenfalls als sensible Betriebsdokumentation behandelt werden.

## D-020 Operator-only Host-Ingress per `nftables`

- Anforderung: Die Proxmox-Web-UI muss operator-only bleiben; allgemeine Zonen duerfen keinen regulaeren Management-Zugriff auf den Host erhalten.
- Gewaehlte Loesung: Das Host-Regelwerk `table inet ailab` arbeitet mit `policy drop` fuer `input` und `forward`. Auf `vmbr0` sind nur `10.0.2.2 -> tcp/22,8006` erlaubt; auf `vmbr10` ist nur `10.10.10.10 -> tcp/22` erlaubt. Aus der Monitoring-Zone gibt es keinen Pfad zur Proxmox-Web-UI auf `tcp/8006`.
- Sicherheitsbegruendung: Damit bleibt ein enger, dokumentierter Operator-Pfad erhalten, waehrend Management- und Monitoring-Endpunkte gegenueber den internen Zonen standardmaessig gesperrt bleiben; `ct-monitoring` beobachtet nur freigegebene Exporter und keine operator-only Host-Oberflaechen.
- Verworfene Alternative: breite Erreichbarkeit von `22`, `8006`, `111` und `3128` mit ausschliesslichem Vertrauen auf Dienstauthentisierung.
- Offenes Restrisiko: Die Daemons lauschen weiter auf Host-Interfaces; ein Ausfall oder Fehl-Laden des `nftables`-Regelwerks wuerde die Schutzwirkung schlagartig reduzieren.

## D-021 Statischer Dual-Homing-Pfad fuer `101 ct-tor-gateway`

- Anforderung: Der Admin-Zugriff ueber Tor soll funktionieren, ohne zusaetzliche Host- oder Hypervisor-NAT-Pfade zu eroefnen.
- Gewaehlte Loesung: `101` ist fest an `vmbr0` mit `10.0.2.101/24` und an `vmbr10` mit `10.10.10.10/24` angebunden; der Host akzeptiert von `10.10.10.10` nur `tcp/22`.
- Sicherheitsbegruendung: Das schafft einen schmalen, reproduzierbaren Transitpfad fuer Admin-SSH, statt den Host breit in interne Zonen zu exponieren oder auf unvorhersehbares DHCP-Verhalten zu vertrauen.
- Verworfene Alternative: DHCP auf `vmbr0` fuer `101` oder direkter Management-Zugriff aus allgemeinen Zonen auf den Host.
- Offenes Restrisiko: `101` wird zum kritischen Admin-Relay; Fehlkonfiguration oder Kompromittierung dieser CT beeintraechtigen die Remote-Bedienbarkeit direkt.

## D-022 Hidden-Service-Konfiguration direkt in `/etc/tor/torrc`

- Anforderung: Der Admin-Onion-Service muss auf der realen Debian-13-Containerbasis sicher geladen werden.
- Gewaehlte Loesung: Die Hidden-Service-Definition wurde direkt in `/etc/tor/torrc` hinterlegt, nachdem der geplante `torrc.d`-Drop-in in dieser Basis nicht geladen wurde.
- Sicherheitsbegruendung: Das vermeidet eine Scheinkonfiguration mit ungenutzter Drop-in-Datei und stellt sicher, dass der effektive Tor-Zustand dem dokumentierten Aufbau entspricht.
- Verworfene Alternative: an `torrc.d` festhalten und annehmen, dass die Drop-ins spaeter automatisch aktiv werden.
- Offenes Restrisiko: Spaetere Paket- oder Basisimage-Aenderungen koennen den Tor-Ladepfad erneut beeinflussen und muessen deshalb vor einem Produktivtransfer nachvalidiert werden.

## D-023 VM-Zonenvalidator ueber Artefakte statt dauerhaften Online-Pfad

- Anforderung: Die App- und Bitcoin-VMs muessen ihre Netzwerkabschottung nachweisen, obwohl `ailab2` nur `kvm=0` und unzuverlaessige ACPI-/Poweroff-Rueckmeldungen bietet.
- Gewaehlte Loesung: Jede VM schreibt den Abschnitt-04-Portcheck in die lokale Disk; der Host extrahiert die Artefakte anschliessend offline und nutzt fuer haengende QEMU-Zustaende nur einen begrenzten Stop-Fallback.
- Sicherheitsbegruendung: So bleibt die Validierung reproduzierbar und bleibt innerhalb der isolierten Test-VM, ohne breitere temporaere Netzpfade oder laengere interaktive Online-Sessions zu oeffnen.
- Verworfene Alternative: laenger laufende Online-Validierung ueber generische Zusatz-NICs oder ungebremste manuelle Konsolen-Sitzungen.
- Offenes Restrisiko: Timing- und Shutdown-Verhalten unter TCG bleiben nur ein Referenznachweis und muessen auf echter KVM-Hardware gesondert bestaetigt werden.

## D-024 Admin-Onion nur mit v3-Client-Authorisierung

- Anforderung: Der administrative Tor-Zugriff soll nicht nur funktional, sondern auf einen sehr kleinen Betreiberkreis begrenzt sein.
- Gewaehlte Loesung: Der Host-SSH-Onion-Service in `101` akzeptiert nur noch explizit autorisierte v3-Clients; auf `ailab2` verbleibt genau ein root-only Test-Operator-Artefakt ausserhalb von `outputs` und ausserhalb des IaC-Pfads.
- Sicherheitsbegruendung: Damit reicht die reine Kenntnis der Onion-Adresse nicht mehr aus; der Remote-Admin-Pfad ist zusaetzlich an ein separates Client-Auth-Artefakt gebunden und die verbleibende private Operator-Datei liegt nicht in den Doku- oder IaC-Pfaden.
- Verworfene Alternative: Offen belassener Admin-Onion nur mit Onion-Adress-Secrecy oder breitere Testverteilung mehrerer Client-Artefakte.
- Offenes Restrisiko: Der lokale Host-SSH-Pfad bleibt wegen der Scope-Vorgabe mit unveraenderter Host-Authentisierung bestehen und ist deshalb nicht vollstaendig durch diese Massnahme geloest.

## D-025 `nftables` als einzige wirksame Host-Schutzschicht

- Anforderung: Der Host-Schutz soll auf einer klaren, zentralen und spaeter driftarmen Betriebsschicht beruhen.
- Gewaehlte Loesung: `nftables` bleibt enabled/active und ist das alleinige Source-of-Truth-Regelwerk; `pve-firewall` wurde disabled/stopped und ist nicht mehr parallel wirksam.
- Sicherheitsbegruendung: Das beseitigt Doppelpflege und die bisherige Unklarheit zwischen Proxmox-Firewallzustand und effektivem Host-Filterpfad.
- Verworfene Alternative: Paralleler Weiterbetrieb von `pve-firewall` bei logisch deaktivierter Policy neben einem separaten `nftables`-Regelwerk.
- Offenes Restrisiko: Faellt das Laden oder Anwenden von `nftables` aus, verbreitert sich die Host-Erreichbarkeit sofort; der Schutz haengt damit bewusst an einer einzigen, aber klar definierten Schicht.

## D-026 `101` nur als sanitisierter Rebuild-Backupfall

- Anforderung: `101 ct-tor-gateway` darf nicht als Vollbackup die Hidden-Service-Identitaet, Client-Auth-Dateien oder wiederverwendbare Tor-Keys vervielfaeltigen.
- Gewaehlte Loesung: `101` wird nicht automatisiert per `vzdump` gesichert. Stattdessen landen nur `pct config 101`, Paketmanifest, `/etc/tor/torrc`, `/etc/network/interfaces`, `/etc/default/prometheus-node-exporter`, relevante Systemd-Overrides und ein ausdruecklicher `EXCLUSIONS.txt`-Hinweis im Borg-Archiv.
- Sicherheitsbegruendung: So bleibt der Restore von `101` ein bewusster Rebuild mit neuer Onion-Identitaet und neuer Client-Authorisierung, statt einen sensiblen Hidden-Service-Key ungeprueft wiederzuverwenden.
- Verworfene Alternative: Vollstaendiger Container-Dump von `101` in dasselbe Backup-Repository wie die uebrigen Strukturartefakte.
- Offenes Restrisiko: Der Rebuild-Fall ist sicherer, aber langsamer und setzt saubere Restore-Dokumentation sowie neue Tor-Runtime-Artefakte voraus.

## D-027 Backup-Pfad Host -> `104` nur ueber `borgrepo`

- Anforderung: Der Host-zu-Backup-Pfad muss auf einen dedizierten Account, einen festen Zweck und root-only-Runtime-Artefakte verengt werden.
- Gewaehlte Loesung: `104` nutzt den Account `borgrepo` mit `AuthenticationMethods publickey`, `ForceCommand /usr/bin/borg serve --restrict-to-path /srv/backup/repos/host`, `PermitTTY no`, `AllowTcpForwarding no`, `AllowAgentForwarding no`, `AllowStreamLocalForwarding no` und `PasswordAuthentication no`. Host-seitig liegen private SSH- und Borg-Artefakte root-only unter `/root/ailab-runtime/borg-host-to-104`, nicht in `outputs` und nicht im IaC-Pfad.
- Sicherheitsbegruendung: Das reduziert den Pfad auf einen einzelnen, gut pruefbaren Backupzweck und verhindert Shell-, PTY- und Forwarding-Nutzung fuer diesen Account.
- Verworfene Alternative: Nutzung von `root` oder eines generischen SSH-Users mit Shell-Zugang auf `104`.
- Offenes Restrisiko: Das Backupziel liegt weiterhin auf demselben Testhost; bei Totalverlust von `ailab2` gehen Quelle und Backupziel gemeinsam verloren.

## D-028 Monitoring nur ueber explizite Exporter-Pfade

- Anforderung: Monitoring soll Zonenmetriken lesen koennen, ohne die Proxmox-Web-UI oder breite Host-Ports freizugeben.
- Gewaehlte Loesung: Host- und Gast-Exporter binden nur an `10.30.30.1:9100`, `10.10.10.10:9100` und `10.40.40.104:9100`. Das zentrale `nftables`-Regelwerk erlaubt nur `ct-monitoring -> host/101/104 tcp/9100`; `8006/tcp` bleibt aus der Monitoring-Zone blockiert.
- Sicherheitsbegruendung: Damit entsteht nur der benoetigte lesende Pfad fuer Metriken, waehrend Management-Oberflaechen operator-only bleiben.
- Verworfene Alternative: Exporter auf `0.0.0.0` mit ausschliesslichem Vertrauen auf Zonennetz oder Monitoring-Zugriff auf `8006`.
- Offenes Restrisiko: `ct-monitoring` bleibt ein privilegierter Beobachter mehrerer Zonen; eine Kompromittierung dieser CT verengt, aber beseitigt den Einblick in Systemmetadaten nicht.

## D-029 Restore-Validierung nur als Smoke-Restore

- Anforderung: Der Restore-Nachweis fuer diesen Abschnitt darf keine laufenden Gaeste gefaehrden und keinen destruktiven Vollrestore ausloesen.
- Gewaehlte Loesung: Validiert wird ausschliesslich ueber `borg list` plus Extraktion einer kleinen Dateimenge in ein temporaeres Host-Verzeichnis. Weder `pct restore` noch ein Vollrestore gegen laufende IDs werden im Abschnitt ausgefuehrt.
- Sicherheitsbegruendung: Das prueft Repository, Entschluesselung, Archivkonsistenz und den Zugriffspfad, ohne die Testumgebung instabil zu machen.
- Verworfene Alternative: Vollstaendiger Restore laufender LXCs oder Restore ueber bestehende Gast-IDs.
- Offenes Restrisiko: Ein Smoke-Restore beweist nicht die volle Dauer und Operabilitaet eines spaeteren Grossrestores; produktionsnahe Restore-Proben bleiben spaeter notwendig.

## D-030 `101` bekommt explizite Rueckroute zur Monitoring-Zone

- Anforderung: Der Exporter in `101` soll fuer `ct-monitoring` erreichbar sein, obwohl `101` seinen Default-Gateway absichtlich ueber `eth0` auf `vmbr0` behaelt.
- Gewaehlte Loesung: `101` erhaelt zusaetzlich die persistente Route `10.30.30.0/24 via 10.10.10.1 dev eth1`.
- Sicherheitsbegruendung: Damit bleibt der Default-Pfad fuer Tor/NAT unveraendert, waehrend nur die benoetigte Monitoring-Antwort gezielt ueber das interne Infrastruktur-Interface zurueckgeht.
- Verworfene Alternative: Umhaengen des Default-Gateways von `101` auf `vmbr10` oder Verzicht auf Monitoring fuer `101`.
- Offenes Restrisiko: Aendern sich Adressierung oder Zonenzuordnung spaeter, muss die statische Rueckroute explizit mitgezogen und erneut validiert werden.

## D-031 Bind-sensitive Dienste warten explizit auf ihre Zonen-IP

- Anforderung: Prometheus-, `ntfy`- und Exporter-Dienste sollen nach Container-Neustarts nicht an noch nicht gesetzten IP-Adressen scheitern.
- Gewaehlte Loesung: `101`, `103` und `104` erhalten `ailab-wait-ip.sh` sowie Unit-Drop-ins mit `ExecStartPre`, `Restart=on-failure`, `RestartSec=5s` und deaktivierter Start-Limit-Drossel fuer die an feste Zonenadressen gebundenen Dienste.
- Sicherheitsbegruendung: Das haelt die enge Bindung an Zonenadressen bei, ohne die Zuverlaessigkeit von Reboots dem Timing von Interface-Initialisierung zu ueberlassen.
- Verworfene Alternative: Rueckkehr zu `0.0.0.0`-Bindings oder Verlassen auf manuelle Neustarts nach jedem Reboot.
- Offenes Restrisiko: Die Loesung haengt an stabilen Interface-Namen und statischen Adressen; veraendern sich diese, muessen die Drop-ins angepasst werden.

## D-032 Bitcoin auf `203/204` nur als dateibasierte Dummy-Simulation

- Anforderung: Das Bitcoin-Konzept soll Online-/Offline-Rollen, Watch-only und PSBT-Fluss praktisch abbilden, ohne reale Seeds, Wallets oder produktive Signing-Artefakte auf `ailab2` zu materialisieren.
- Gewaehlte Loesung: `203` bildet nur den Watch-only-/Referenzkontext ab; `204` bildet nur die Hot-Service-Simulation ab. Beide Rollen arbeiten ausschliesslich mit Dummy-Dateien fuer Watch-only-Bundle, unsigned PSBT, signed Dummy-Import und Broadcast-Receipt. Reale Bitcoin-Daemons wie Bitcoin Core oder Electrs werden in diesem Run nicht ausgerollt.
- Sicherheitsbegruendung: Damit bleibt der komplette Bitcoin-Teil innerhalb der vorgegebenen Dummy-only-Grenze und reduziert gleichzeitig den Blast Radius einer Host- oder Gastkompromittierung.
- Verworfene Alternative: Echte Bitcoin-Core-/Electrs-Installation oder echte Wallet-Artefakte in der Test-VM.
- Offenes Restrisiko: Die Betriebslogik ist validiert, aber keine echte Interoperabilitaet mit produktiven Bitcoin-Komponenten.

## D-033 Offline-Signer nur ueber root-only Host-Handoff simulieren

- Anforderung: Der Cold-/Offline-Schritt muss klar getrennt bleiben, obwohl in diesem Run kein echtes air-gapped System mit echten Schluesseln gebaut werden darf.
- Gewaehlte Loesung: Der Offline-Handoff wird ausschliesslich ueber `/root/ailab-runtime/bitcoin-sim-offline` simuliert. Dort liegen Watch-only-Export, unsigned Dummy-PSBT, signed Dummy-Artefakt und Receipt root-only; weder `outputs` noch der IaC-Pfad enthalten diese Runtime-Dateien.
- Sicherheitsbegruendung: Das trennt die Rollen sichtbar, verhindert versehentliche Verteilung ueber Doku-/IaC-Pfade und bildet den spaeteren manuellen PSBT-Handoff diszipliniert nach.
- Verworfene Alternative: Ablage der Handoff-Artefakte im IaC-Pfad, in `outputs` oder direkt innerhalb eines der Bitcoin-Gaeste.
- Offenes Restrisiko: Der Offline-Schritt bleibt organisatorisch getrennt, aber technisch weiterhin auf demselben Testhost simuliert.

## D-034 TCG-/EFI-Bootpfad fuer `203/204` explizit entschärfen

- Anforderung: Die kleinen Bitcoin-VMs muessen ihre Validator-Boots in der VirtualBox-/TCG-Testbasis reproduzierbar abschliessen, ohne an einem irrelevanten EFI-Mount zu scheitern.
- Gewaehlte Loesung: Auf `203` und `204` wird `/boot/efi` in `/etc/fstab` mit `nofail,x-systemd.device-timeout=1s` gefahren; zusaetzlich erhielt `204` ein deutlich laengeres Wait-Fenster fuer die Validator-Boots.
- Sicherheitsbegruendung: Das beseitigt in dieser nicht-produktiven Testbasis einen Bootblocker, der nichts mit der eigentlichen Bitcoin-Simulationslogik zu tun hat, und verhindert damit Scheinergebnisse durch Emergency- oder Timeout-Pfade.
- Verworfene Alternative: Unveraenderter EFI-Mount mit wiederholten Abbruechen oder breite manuelle Eingriffe waehrend der Validator-Boots.
- Offenes Restrisiko: Der TCG-/EFI-Bootpfad dieser Test-VM bleibt kein Beweis fuer spaeteres Produktivverhalten unter echter KVM-Hardware.

## D-035 Fehleranalyse trennt Testbed-Rauschen von finalen Architekturfehlern

- Anforderung: Der Fehleranalyse-Abschnitt soll reale Fehler aus den Abschnitten 03 bis 06 priorisieren, ohne Testbed-Nachlaeufe oder bereits bereinigte Validatorprobleme mit offenen Sicherheitsluecken zu vermischen.
- Gewaehlte Loesung: Der Benchmark wertet nur die tatsaechlichen Artefakte aus, trennt den final validierten Endzustand von historischen Nachlaeufen und klassifiziert TCG-/Loop-/Resume-Probleme bewusst als P3-Testbed-Robustheit statt als offene Architekturverletzung.
- Sicherheitsbegruendung: So bleiben Prioritaeten belastbar, und spaetere Härtungsmassnahmen zielen auf echte Schutzluecken statt auf Fehlinterpretationen eines kleinen VirtualBox-/TCG-Referenzaufbaus.
- Verworfene Alternative: Jede Validator-Wiederholung pauschal als offene Sicherheits- oder Architekturstoerung behandeln.
- Offenes Restrisiko: Neue Folgeabschnitte koennen weitere Fehlerbilder erzeugen, die gesondert neu bewertet werden muessen.
