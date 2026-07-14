# Fehleranalyse Benchmark

## Zweck

- Getrennte Analyse der realen Fehlerartefakte aus den bereits umgesetzten Abschnitten
- Klare Trennung zwischen historischem Fehlerbild und final validiertem Endzustand
- Priorisierung nach Sicherheitswirkung, Betriebswirkung und dauerhafter Mitigation

## Analysebasis

- Es wurden keine separaten neuen Fehlerartefakte bereitgestellt.
- Der Benchmark stuetzt sich deshalb auf die tatsaechlich angefallenen Logs und Validatorartefakte aus:
  - `/root/ailab2-iac/section-03-config`
  - `/root/ailab2-iac/section-04-network-tor`
  - `/root/ailab2-iac/section-05-backup-monitoring`
  - `/root/ailab2-iac/section-06-bitcoin-simulation`
  - `outputs/implementation-log.md`
  - `outputs/validator-notes.md`
  - `outputs/decision-log.md`
  - `outputs/final-summary.md`

## Bewertungsraster

- P1: Sicherheitsluecke, Datenverlust, Dienststillstand oder Scope-Verstoss im finalen Endzustand
- P2: Funktionaler oder prozessualer Fehler mit klarer Sicherheits- oder Betriebswirkung
- P3: Testbed-, Robustheits- oder Dokumentationsproblem mit niedrigerem unmittelbarem Schaden

## Ergebnis auf einen Blick

- Keine offenen P1-Befunde im final validierten Endzustand.
- Im analysierten Korpus bleiben 6 P2- und 3 P3-Befunde relevant.
- Der Schwerpunkt der P2-Befunde lag auf:
  - sensiblen Admin-Metadaten in IaC-/Validatorpfaden
  - unvollstaendigen Bootstrap-Annahmen fuer Backup und Monitoring
  - Routing- und Bootpfad-Problemen in kleinen Testgaesten
- Der Schwerpunkt der P3-Befunde lag auf:
  - TCG-/Loop-/LVM-bedingter Validatorfragilitaet
  - Resume-Problemen bei Mount- und Loop-Zustaenden
  - einer falschen Annahme ueber die aktive Tor-Konfigurationsschicht

## Priorisierte Befunde

### F-001 P2 Sensible Admin-Onion-Metadaten landeten kurz im IaC-Pfad

- Belege:
  - `outputs/validator-notes.md` dokumentiert, dass zwei fruehere IaC-Validatorartefakte aus Abschnitt 04 die konkrete Admin-Onion-Adresse enthielten und spaeter redigiert wurden.
  - Die aktuelle Nachvalidierung prueft explizit, dass weder Onion-Adresse noch `.auth_private`-Inhalt in `outputs` oder `/root/ailab2-iac` verbleiben.
- Ursache:
  - Ein Validator schrieb laufzeitnahe Admin-Metadaten in einen langlebigen Doku-/IaC-Pfad.
- Wirkung:
  - Kein unmittelbarer Auth-Bypass, aber unnoetige Offenlegung einer kleinen operator-only-Admin-Adresse.
- Status:
  - Behoben.
- Benchmark-Urteil:
  - Als Doku-/Prozess-Sicherheitsfehler behandeln, nicht als Fehler des Tor-Designs selbst.

### F-002 P2 Der erste Borg-Backup-Lauf war wegen unvollstaendiger Runtime nicht belastbar

- Belege:
  - `/root/ailab2-iac/section-05-backup-monitoring/logs/section05-recover.log` beginnt mit `Korrigiere Borg-runtime und known_hosts`.
  - `/root/ailab2-iac/section-05-backup-monitoring/validation/borg-create.txt` weist erst danach den finalen Repository-Pfad `ssh://borgrepo@10.40.40.104/srv/backup/repos/host` nach.
- Ursache:
  - Der dedizierte Backup-Pfad war zwar konzipiert, aber fuer den ersten echten Lauf noch nicht vollstaendig mit Runtime-Artefakten und SSH-Vertrauensmaterial vorbereitet.
- Wirkung:
  - Ein geplanter automatisierter Backup-Job waere beim ersten Lauf unsauber gestartet oder haette abgebrochen.
- Status:
  - Behoben.
- Benchmark-Urteil:
  - Backup-Pfade muessen vor dem ersten Timer-Lauf einen vollstaendigen Preflight fuer `known_hosts`, Schluesselpfade und Restrict-Command bestehen.

### F-003 P2 `ntfy` war initial nicht startklar, obwohl das Konzept bereits stand

- Belege:
  - `/root/ailab2-iac/section-05-backup-monitoring/logs/section05-recover.log` dokumentiert `Bringe ntfy mit den benoetigten Paketpfaden hoch`.
  - `/root/ailab2-iac/section-05-backup-monitoring/validation/103-ntfy-unit.txt` zeigt die paketseitige Unit und den spaeteren Bind-Reliability-Drop-in.
- Ursache:
  - Die reale Paket- und Runtime-Struktur des Dienstes war in der ersten Konfiguration nicht vollstaendig beruecksichtigt.
- Wirkung:
  - Operator-Alerting waere trotz geplanter Monitoring-Topologie kurzfristig ausgefallen.
- Status:
  - Behoben.
- Benchmark-Urteil:
  - Bei operator-only-Diensten reicht ein Architekturplan nicht; paketkonkrete Runtime-Annahmen muessen vor dem finalen Enable geprueft werden.

### F-004 P2 Feste Bindung an Zonenadressen war ohne Startreihenfolge nicht robust

- Belege:
  - `/root/ailab2-iac/section-05-backup-monitoring/logs/section05-bind-reliability-fix.log` dokumentiert den gezielten Nachlauf fuer bind-sensitive Dienste.
  - Die Drop-ins `/root/ailab2-iac/section-05-backup-monitoring/staging/101-node-exporter-bind-fix.conf`, `103-bind-fix.conf` und `104-node-exporter-bind-fix.conf` enthalten `ExecStartPre=/usr/local/sbin/ailab-wait-ip.sh ...` sowie `Restart=on-failure`.
- Ursache:
  - Dienste banden bewusst nur an ihre Zonenadresse, starteten aber teilweise vor der vollstaendigen IP-Initialisierung.
- Wirkung:
  - Nach Neustarts drohten Monitoring-Blindstellen ohne echte Sicherheitsverbesserung.
- Status:
  - Behoben.
- Benchmark-Urteil:
  - Enge Listen-Bindings bleiben richtig, brauchen aber explizite Abhaengigkeit von der Netzinitialisierung.

### F-005 P2 Der dual-homed Gast `101` hatte anfangs keinen sauberen Rueckweg zur Monitoring-Zone

- Belege:
  - `/root/ailab2-iac/section-05-backup-monitoring/validation/101-routes-after-monitoring-route.txt` zeigt final die gezielte Route `10.30.30.0/24 via 10.10.10.1 dev eth1`.
- Ursache:
  - `101` behaelt absichtlich seinen Default-Gateway ueber `eth0` fuer Tor/NAT; ohne explizite Zusatzroute waeren Monitoring-Antworten nicht deterministisch ueber `eth1` zurueckgelaufen.
- Wirkung:
  - Monitoring aus `103` waere unzuverlaessig gewesen und haette im Fehlerfall unnoetige Egress-Unklarheit erzeugt.
- Status:
  - Behoben.
- Benchmark-Urteil:
  - Dual-homed Sicherheitsgaeste brauchen explizite Rueckrouten fuer jede erlaubte Beobachtungs- oder Management-Beziehung.

### F-006 P2 Der Bitcoin-Validator auf `204` scheiterte zweimal, bevor der Testbed-Bootpfad stabil war

- Belege:
  - `/root/ailab2-iac/section-06-bitcoin-simulation/logs/section06-apply.log` meldet zweimal `ERROR: VM 204 is missing marker /var/lib/ailab/bitcoin-sim/phase1.done.`
  - Dieselbe Logdatei endet spaeter mit `Section 06 validation succeeded.`
  - Die finalen Zustandsdateien `/root/ailab2-iac/section-06-bitcoin-simulation/validation/204-service-phase1-workflow-state.txt` und `204-service-phase2-workflow-state.txt` zeigen `phase=phase1-unsigned` und `phase=phase2-import-broadcast`.
- Ursache:
  - Das urspruengliche Wait-Fenster war fuer die kleine TCG-VM zu knapp; zusaetzlich blockierte der EFI-Mountpfad in dieser Testbasis den sauberen Boot bis zum Service.
- Wirkung:
  - Zunaechst ein False-Negative im Validator und unklarer Abschnittsstatus, obwohl die eigentliche Dummy-PSBT-Logik korrekt angelegt war.
- Status:
  - Behoben.
- Benchmark-Urteil:
  - Der Befund lag im Testbed-Bootpfad, nicht in der Rollen- oder Rechtearchitektur des Bitcoin-Teils.

### F-007 P3 Die `vmbr90`-Validierung auf `203` erzeugte False-Negatives und LVM-Retry-Reibung

- Belege:
  - `/root/ailab2-iac/section-03-config/logs/run-20260707T150245Z-vm-chroot.log` zeigt beim ersten Boot `cp: cannot stat ... vmbr90-port-checks.log`.
  - Die Retry-Logs `/root/ailab2-iac/section-03-config/logs/run-20260707T154845Z-vm203-retry.log` und `run-20260707T160257Z-vm203-retry3.log` melden jeweils `Logical volume ... in use`.
- Ursache:
  - Der Validator nahm einen sofort verfuegbaren Artefaktpfad an, waehrend der Gast und die Loop-/LVM-Ressourcen noch nicht sauber freigegeben waren.
- Wirkung:
  - Mehrere Wiederholungen und ein verrauschtes Signal ueber den tatsaechlichen Zustand der Provisionierung.
- Status:
  - Operativ bereinigt, aber als Testbed-Fragilitaet dokumentiert.
- Benchmark-Urteil:
  - Kein Architekturfehler der Zonentrennung, sondern ein Robustheitsproblem des Kurzboot-Validators.

### F-008 P3 Der Resume-/Finalize-Pfad in Abschnitt 04 war nicht ausreichend idempotent

- Belege:
  - `/root/ailab2-iac/section-04-network-tor/logs/run-20260707T173159Z-resume.log` zeigt `Can't lookup blockdev` und einen fehlenden Zielpfad unter `etc/systemd/network`.
  - `/root/ailab2-iac/section-04-network-tor/logs/run-20260707T173633Z-resume2.log` zeigt einen weiteren Mount-Fehler `wrong fs type, bad option, bad superblock`.
  - Erst `/root/ailab2-iac/section-04-network-tor/logs/run-20260707T173925Z-resume3.log` bootet `203` wieder sauber in die Validierung.
- Ursache:
  - Der Resume-Pfad ging nicht robust genug mit vorigen Loop-, Mount- und Extraktionszustaenden um.
- Wirkung:
  - Unnoetige Nachlaeufe und das Risiko, Testbed-Fehler als Netzwerk- oder Tor-Probleme fehlzuinterpretieren.
- Status:
  - Operativ abgeschlossen, aber weiter als Robustheitsthema relevant.
- Benchmark-Urteil:
  - Resume- und Recovery-Pfade brauchen dieselbe Sorgfalt wie der Erstlauf, sonst entsteht unnoetige Drift im Betriebsbild.

### F-009 P3 Die urspruengliche `torrc.d`-Annahme passte nicht zur Debian-13-Basis

- Belege:
  - `outputs/decision-log.md` unter `D-022` dokumentiert, dass der geplante `torrc.d`-Drop-in in dieser Basis nicht geladen wurde.
  - `outputs/validator-notes.md` und `outputs/implementation-log.md` halten fest, dass die effektive Hidden-Service-Konfiguration deshalb direkt in `/etc/tor/torrc` liegt.
- Ursache:
  - Eine Plattformannahme ueber die aktive Tor-Konfigurationsschicht war falsch.
- Wirkung:
  - Ohne Korrektur haette die Doku eine andere Schicht beschrieben als die tatsaechlich wirksame Runtime.
- Status:
  - Behoben.
- Benchmark-Urteil:
  - Konfigurationsmodelle muessen immer gegen den real geladenen Dienstzustand validiert werden, nicht nur gegen die geplante Dateistruktur.

## Querschnittserkenntnisse

- Runtime-nahe Admin-Metadaten gehoeren nicht in langlebige IaC- oder Output-Pfade.
- Enge Listen-Bindings an Zonenadressen brauchen explizite IP- und Bootabhaengigkeiten.
- Dual-homed Sicherheitsgaeste brauchen fuer jede erlaubte Gegenstelle einen bewusst dokumentierten Rueckweg.
- In dieser Test-VM muessen TCG-, EFI-, Loop- und LVM-Artefakte strikt von echten Architektur- oder Sicherheitsfehlern getrennt werden.

## Ableitungen fuer Folgeabschnitte

- Such- und Redaction-Checks fuer `.onion`- und `.auth_private`-Artefakte in `outputs` und IaC beibehalten.
- Backup- und Monitoring-Pfade vor jedem ersten Enable mit `known_hosts`-, Runtime-, Bind- und Routing-Preflight absichern.
- Restore-, Resume- und Kurzboot-Validatoren weiterhin als testbed-sensitive Hilfspfad behandeln und nicht mit Produktivbeweisen verwechseln.

## Status

- Benchmark erstellt und auf die realen Artefakte aus den Abschnitten 03 bis 06 abgestuetzt.
- Keine Live-Aenderungen auf `ailab2` fuer diesen Abschnitt vorgenommen.
