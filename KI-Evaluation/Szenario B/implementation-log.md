# Implementation Log

## 2026-07-07 Initiale Phase

- Lokale Arbeitsumgebung geprueft; keine bereitgestellten Zusatzartefakte im Workspace gefunden.
- SSH-Verbindung zu `ailab2` erfolgreich aufgebaut.
- Ausschliesslich lesende Bestandsaufnahme ausgefuehrt.
- Noch keine Konfigurations- oder Dienstaenderung auf der VM vorgenommen.
- Mandantenanforderungen aus dem Folgeprompt in die Architekturplanung uebernommen.
- Architekturdetail freigegeben fuer reine Dokumentationsumsetzung.
- Dokumentiert: Schutzbedarf, Zugriffspfade, Secrets-Klassen, Backup-/Restore-Klassen und Deny-by-default-Matrix.
- Dokumentiert: Proxmox-Web-UI operator-only; Grafana, Alertmanager und `ntfy` operator-only; Monitoring-Endpunkte keine allgemeinen Nutzerdienste.
- Dokumentiert: Bitcoin auf `ailab2` ausschliesslich als Dummy-/Simulationskontext ohne echte Seeds, `xprv`, `wallet.dat`, produktive Private Keys oder produktive API-Schluessel.
- Dokumentations-Validator ausgefuehrt; Nachweise in `validator-notes.md` ergaenzt.
- Gastgrundlagen / Provisionierung geplant: Bridges, Phase-1-Ressourcen, Basisartefakte, Snapshot-Strategie und Deferred-Liste dokumentiert.

## 2026-07-07 Gastgrundlagen / Provisionierung umgesetzt

- Live-Ressourcen vor Umsetzung erneut geprueft: ca. `6.3 GiB` verfuegbarer RAM, `local-lvm` voll frei, keine bestehenden Gaeste.
- Host-Netz fuer die Zielzonen erweitert:
  - `vmbr10` Infrastruktur
  - `vmbr20` Anwendungen
  - `vmbr30` Monitoring
  - `vmbr40` Backup
  - `vmbr50` Bitcoin
- LXC-Basis geladen:
  - Template: `debian-13-standard_13.1-2_amd64.tar.zst`
  - lokaler SHA-512: `5aec4ab2ac5c16c7c8ecb87bfeeb10213abe96db6b85e2463585cea492fc861d7c390b3f9c95629bbf690b95e9dfe1037207fc69c0912429605f208d5cb2621f8`
- VM-Basis geladen:
  - Image: `debian-13-genericcloud-amd64-20250814-2204.qcow2`
  - verifizierter SHA-512 laut `SHA512SUMS`: `d76122c87c940d1ab9334f4307c98c01dc42f0b49a20cddf278d59b92d34ab63d05ac1f40dffda3dd2d32e381f097706eee6ccbf79a596bfb2cbb3d83c635ae35`
  - erwartete `SHA512SUMS.sign` am gepinnten Cloud-Pfad nicht vorhanden, deshalb nur Hash-Pruefung plus dokumentiertes Restrisiko
- LXC-Gaeste erstellt:
  - `101 ct-tor-gateway`
  - `102 ct-edge-proxy`
  - `103 ct-monitoring`
  - `104 ct-backup`
- VM-Basetemplate erstellt:
  - `9000 tmpl-debian13-cloud`
- VM-Gaeste erstellt:
  - `201 vm-apps-core`
  - `202 vm-apps-extended`
  - `203 vm-bitcoin-node`
  - `204 vm-bitcoin-service`
- LXC-Gaeste unprivileged erstellt; aktivierte Zusatzfeatures explizit auf `nesting=0,keyctl=0,fuse=0,mknod=0` gesetzt.
- Alle Gaeste mit `onboot: 0` konfiguriert.
- Alle Gaeste fuer Baseline kurz gestartet und danach wieder in `stopped` ueberfuehrt.
- Fuer die vier VMs war `kvm=0` als lokale Ausweichstrategie noetig, weil in dieser VirtualBox-Test-VM kein nutzbares Nested-KVM bereitsteht.
- Baseline-Snapshots `post-provision-base` fuer alle acht Gaeste angelegt.
- Tatsachlicher Storage-Stand nach Provisionierung:
  - `local`: ca. `11.25%` belegt
  - `local-lvm`: ca. `12.25%` real belegt
- Thin-LVM meldet erwartbare Warnungen zur virtuellen Summengroesse der angelegten Baseline-Snapshots; realer Verbrauch bleibt derzeit niedrig.

## 2026-07-07 Konfiguration umgesetzt

- Host-seitiger IaC-Pfad `/root/ailab2-iac` mit `README.md`, Abschnitts-README und `guest-baseline.tsv` angelegt; ausdrueckliche No-Secrets-Regel hinterlegt.
- Baseline-Niveau bewusst als echte OS-Haertung umgesetzt und nicht nur als Paketindex-Refresh:
  - `apt-get update`
  - `apt-get -y --with-new-pkgs upgrade`
- `101 ct-tor-gateway` blieb fuer diesen Abschnitt absichtlich unveraendert und die `vmbr0`-Anbindung wurde nicht angefasst.
- Temporaerer Paketversorgungspfad eingerichtet:
  - Bridge `vmbr90` auf `172.31.90.1/24`
  - host-lokales `apt-cacher-ng` ausschliesslich auf `172.31.90.1:3142`
  - temporare `nftables`-Tabelle `ailab_vmbr90`, die von `vmbr90` nur `tcp/3142` zum Host-IP erlaubt und sonst Host-Input sowie Forwarding verwirft
- LXC-Gaeste `102`, `103` und `104` wurden ueber ein temporaeres `net9` an `vmbr90` angeschlossen, mit aktualisierter Basis versehen und danach wieder gestoppt.
- Die drei LXC-Gaeste erhielten keine zusaetzlichen Laufzeitpakete; umgesetzt wurden nur Basis-OS-Updates und Minimalziele:
  - `Etc/UTC`
  - Journald-Limits
  - `/etc/ailab`
  - `/etc/ailab/secrets` als Platzhalter
  - rollenbezogene `/srv`-Pfade
  - Gastrollen-Metadaten
- Die VMs `201`, `202`, `203` und `204` wurden wegen `kvm=0` und unzuverlaessiger QGA-/Cloud-Init-Interaktion per Offline-Chroot vorbereitet und nur kurz fuer den `vmbr90`-Validator gebootet.
- Die vier VMs erhielten ausschliesslich zusaetzlich:
  - `qemu-guest-agent`
  - `cloud-guest-utils`
- Gemeinsame Minimalziele fuer `201` bis `204`:
  - `Etc/UTC`
  - Journald-Limits
  - `/etc/ailab`
  - `/etc/ailab/secrets` als Platzhalter
  - rollenbezogene `/srv`-Pfade
  - `guest-role.txt`
  - Hostname/FQDN-Eintrag
- Fuer `203 vm-bitcoin-node` und `204 vm-bitcoin-service` wurde zusaetzlich `/etc/ailab/bitcoin-dummy-only.txt` angelegt; keine Wallet-Dateien, keine Seeds, keine `xprv`, keine produktiven API-Schluessel.
- Pro geaendertem Gast wurde ein Paket- und Versionsmanifest unter `/root/ailab2-iac/section-03-config/manifests` gesichert:
  - `102-ct-edge-proxy-package-manifest.txt`
  - `103-ct-monitoring-package-manifest.txt`
  - `104-ct-backup-package-manifest.txt`
  - `201-vm-apps-core-package-manifest.txt`
  - `202-vm-apps-extended-package-manifest.txt`
  - `203-vm-bitcoin-node-package-manifest.txt`
  - `204-vm-bitcoin-service-package-manifest.txt`
- Pro geaendertem Gast wurde ein `vmbr90`-Portcheck gesichert; Sollnachweis:
  - `tcp/3142=open`
  - `tcp/22=blocked`
  - `tcp/111=blocked`
  - `tcp/8006=blocked`
  - `tcp/3128=blocked`
- `203 vm-bitcoin-node` benoetigte wegen eines Boot-Timing-Ausreissers unter Softwareemulation einen isolierten Nachlauf; nach Haertung des Validators mit `network-online` plus Proxy-Retry wurde der Nachweis erfolgreich erneut erzeugt.
- Nach Abschluss wurden vollstaendig rueckgebaut:
  - `vmbr90`
  - `apt-cacher-ng`
  - `ailab_vmbr90`
  - temporaere `net9`- und `net1`-NICs
- Alle acht Gaeste enden nach diesem Abschnitt wieder im Zustand `stopped`.
- Fuer alle acht Gaeste existiert jetzt zusaetzlich der Snapshot `post-config-base`.
- Ein verbliebener Loop-Handle aus dem finalen `203`-Extraktionslauf wurde manuell geloest; danach blieben keine offenen Loop-Devices aus diesem Abschnitt zurueck.

## 2026-07-07 Netzwerk / Tor umgesetzt

- Die internen Zonen erhielten jetzt die dokumentierten Host-Gateway-Adressen:
  - `vmbr10` `10.10.10.1/24`
  - `vmbr20` `10.20.20.1/24`
  - `vmbr30` `10.30.30.1/24`
  - `vmbr40` `10.40.40.1/24`
  - `vmbr50` `10.50.50.1/24`
- Host-seitig wurde `net.ipv4.ip_forward=1` ueber `/etc/sysctl.d/99-ailab-routing.conf` aktiviert.
- Das bisherige Host-Regelwerk wurde durch `nftables` als `table inet ailab` mit `policy drop` fuer `input` und `forward` ersetzt.
- Die operator-only-Ingress-Pfade sind jetzt hostseitig auf zwei konkrete Quellen verengt:
  - `vmbr0`: nur `10.0.2.2 -> tcp/22,8006`
  - `vmbr10`: nur `10.10.10.10 -> tcp/22`
- Die bestehende Operator-Erreichbarkeit blieb dabei erhalten:
  - lokaler SSH-Pfad `127.0.0.1:2225`
  - lokaler Web-UI-Pfad `https://127.0.0.1:8012`
- `101 ct-tor-gateway` wurde fuer den Admin-Pfad bewusst dual-homed und statisch konfiguriert:
  - `eth0` auf `vmbr0` mit `10.0.2.101/24`, Gateway `10.0.2.2`, Nameserver `10.0.2.3`
  - `eth1` auf `vmbr10` mit `10.10.10.10/24`
- Der Admin-Onion-Service wurde in `101` erfolgreich aktiviert; die Hidden-Service-Konfiguration liegt direkt in `/etc/tor/torrc`, weil das Debian-13-Basisimage die geplante `torrc.d`-Datei nicht geladen hat.
- Die Validierung zeigt fuer `101` den beabsichtigten Admin-Pfad:
  - `10.10.10.1:22=open`
  - `10.10.10.1:111/8006/3128=blocked`
  - `10.0.2.15:22/111/8006/3128=blocked`
  - `onion/tcp22=open`
- Fuer die internen Zonen wurde der Deny-by-default-Nachweis praktisch erbracht:
  - `102` gegen `10.10.10.1`
  - `103` gegen `10.30.30.1`
  - `104` gegen `10.40.40.1`
  - `201` und `202` gegen `10.20.20.1`
  - `203` und `204` gegen `10.50.50.1`
  - jeweils `tcp/22`, `tcp/111`, `tcp/8006` und `tcp/3128` als `blocked`
- Fuer alle acht Zielgaeste existiert jetzt zusaetzlich der Snapshot `post-network-tor-base`.
- Der Endzustand nach Abschnitt 04 ist:
  - `101` laufend
  - `102`, `103`, `104`, `201`, `202`, `203` und `204` gestoppt
- Der Rollback-Guard aus dem ersten Firewall-/Tor-Lauf wurde nach erfolgreichem Abschluss entfernt.
- Dokumentierte technische Abweichungen und Korrekturen:
  - Die erste 101-Konfiguration mit DHCP auf `vmbr0` destabilisierten den Operator-Pfad; die CT wurde deshalb auf die feste Adresse `10.0.2.101/24` umgestellt.
  - Der erste Abschnitt-04-Finalizer musste wegen `kvm=0`-/TCG-Timing, eines alten `vmbr90`-Validator-Units in `201/202` und verzogerter `loopXp1`-Bereitstellung bei `203` gehaertet und erneut ausgefuehrt werden.
  - Die Snapshot-Tasks lieferten Thin-LVM-Warnungen zur virtuellen Summengroesse, aber alle `post-network-tor-base`-Snapshots wurden erfolgreich angelegt.

## 2026-07-07 Mini-Hardening Admin-Tor / Hostschutz umgesetzt

- Der Host-SSH-Onion in `101` wurde von reiner Onion-Adress-Secrecy auf service-seitige v3-Client-Authorisierung umgestellt.
- Auf dem Host verbleibt genau ein root-only Test-Operator-Artefakt:
  - `/root/ailab-runtime/admin-onion-operator/operator-1.auth_private`
  - Rechte `0600`, Besitzer `root:root`
  - nicht in `outputs` und nicht im IaC-Pfad abgelegt
- In `101` verbleibt genau ein service-seitiger Autorisierungseintrag:
  - `/var/lib/tor/ssh-admin-onion/authorized_clients/operator-1.auth`
  - Rechte `0600`, Besitzer `debian-tor:debian-tor`
- Die alte Drop-in-Datei `/etc/tor/torrc.d/10-ailab-admin-ssh.conf` wurde entfernt; die effektive Hidden-Service-Definition liegt jetzt nur noch einmal in `/etc/tor/torrc`.
- Fuer den Validator wurden in `101` nur temporaere Tor-Clients unter `/root/tor-client-check` gestartet; deren PIDs, Torrcs, DataDirs und Auth-Kopien wurden nach dem Nachweis wieder entfernt.
- `pve-firewall` wurde `disabled` und `stopped`; `nftables` blieb `enabled` und `active` und ist jetzt die einzige wirksame Host-Schutzschicht.
- Zwei alte IaC-Validatorartefakte wurden nachgezogen und um die konkrete Onion-Adresse redigiert, damit keine laufzeitnahe Admin-Adresse im IaC-Pfad verbleibt.
- Der lokale Operator-Pfad blieb bewusst unveraendert nutzbar; das verbleibende Scope-Risiko ist, dass die Host-Authentisierung fuer diesen Pfad weiter `PermitRootLogin yes` und `PasswordAuthentication yes` umfasst.

## Erfasste Basisdaten

- `hostnamectl`: Host `ailab2`, Debian 13, Proxmox-Kernel `7.0.2-6-pve`
- `pveversion -v`: Proxmox VE 9.2.2
- `ip -br addr`, `ip route`, `/etc/network/interfaces`: `vmbr0` auf `10.0.2.15/24`, `nic1` ungenutzt
- `ss -tulpn`: offene TCP-Ports `22`, `111`, `8006`, `3128`
- `pve-firewall status`: `disabled/running`
- `qm list`, `pct list`: keine Gaeste
- `pvesm status`, `lsblk`, `df -hT`, `free -h`: ausreichend freie Ressourcen fuer den Testaufbau

## Naechster geplanter Abschnitt

- Architekturabschnitt abgeschlossen
- Gastgrundlagen / Provisionierung abgeschlossen
- Konfiguration abgeschlossen
- Netzwerk / Tor abgeschlossen
- Mini-Hardening Admin-Tor / Hostschutz abgeschlossen
- Danach Vorbereitung des naechsten freigabepflichtigen Abschnitts `Bitcoin-Konzept`

## 2026-07-07 Backup / Monitoring umgesetzt

- Host-seitige Monitoring-/Backup-Basis ausgerollt:
  - `prometheus-node-exporter` auf `10.30.30.1:9100`
  - Textfile-Metriken via `/usr/local/sbin/ailab-ssh-auth-metrics.sh`
  - `ailab-ssh-auth-metrics.timer`
  - `ailab-backup.service` und `ailab-backup.timer`
- `101 ct-tor-gateway` erweitert:
  - `prometheus-node-exporter` auf `10.10.10.10:9100`
  - persistente Rueckroute `10.30.30.0/24 via 10.10.10.1 dev eth1`
  - sanitisierte Backup-Behandlung statt Vollbackup
- `103 ct-monitoring` ausgerollt:
  - `prometheus` auf `10.30.30.103:9090`
  - `prometheus-alertmanager` auf `10.30.30.103:9093`
  - `prometheus-blackbox-exporter` auf `10.30.30.103:9115`
  - `prometheus-node-exporter` auf `10.30.30.103:9100`
  - `ntfy` operator-only auf `10.30.30.103:2586`
  - Alert-Regeln fuer Target-Down, Backup-Stale, SSH-Failures und `ntfy`-Erreichbarkeit
- `104 ct-backup` ausgerollt:
  - `prometheus-node-exporter` auf `10.40.40.104:9100`
  - dedizierter SSH-Account `borgrepo`
  - `ForceCommand /usr/bin/borg serve --restrict-to-path /srv/backup/repos/host`
  - `PasswordAuthentication no`, `PermitTTY no`, `AllowTcpForwarding no`, `AllowAgentForwarding no`, `AllowStreamLocalForwarding no`
- Host-Runtime-Artefakte fuer Borg liegen root-only unter `/root/ailab-runtime/borg-host-to-104` und wurden bewusst weder in `outputs` noch im IaC-Pfad abgelegt.
- Das lokale Borg-Repository auf `104` ist mit `repokey-blake2` verschluesselt; der finale validierte Archivstand ist `ailab2-20260707T212412Z`.
- Der erste Backup-Lauf scheiterte zunaechst an fehlendem `known_hosts`; danach wurden `known_hosts`, root-only-Rechte und der Borg-Pfad korrigiert und erfolgreich erneut validiert.
- `ntfy` scheiterte zuerst an fehlenden Paketverzeichnissen `/var/cache/ntfy` und `/var/lib/ntfy`; nach Anlage mit `_ntfy:_ntfy` lief der Dienst stabil.
- Nach den CT-Neustarts fielen einige bind-sensitive Dienste wegen noch nicht gesetzter Zonen-IP aus; dafuer wurden auf `101`, `103` und `104` `ailab-wait-ip.sh` und passende Systemd-Drop-ins fuer die betroffenen Services eingefuehrt.
- Die Monitoring-Zielpfade wurden praktisch nachgewiesen:
  - `103 -> 10.30.30.1:9100 = open`
  - `103 -> 10.10.10.10:9100 = open`
  - `103 -> 10.40.40.104:9100 = open`
  - `103 -> 10.30.30.1:{22,111,8006,3128} = blocked`
- Der Host-zu-Backup-Pfad ist praktisch nachgewiesen:
  - `10.40.40.104:22 = open`
  - direkter SSH-Aufruf auf `borgrepo` endet in Borg-Usage statt Shell
- Das sanitisierte Backup von `101` enthaelt final:
  - `/etc/tor/torrc`
  - `/etc/network/interfaces`
  - `/etc/default/prometheus-node-exporter`
  - relevante Systemd-Overrides
  - ausdruecklichen Ausschlusshinweis fuer `/var/lib/tor/ssh-admin-onion/`
- Der temporaere Paketpfad wurde fuer diesen Abschnitt nur als Installationshilfe fuer `103` und `104` benutzt; die massgeblichen Nachweise bleiben:
  - `103-vmbr90.txt`
  - `104-vmbr90.txt`
  - jeweils `tcp/3142=open` und `tcp/22`, `tcp/111`, `tcp/8006`, `tcp/3128` als `blocked`
- Danach wurden vollstaendig entfernt:
  - `vmbr90`
  - `apt-cacher-ng`
  - temporaere `net9`-NICs in `103` und `104`
- Finaler Laufzeitstand nach Abschnitt 05:
  - `101` `running`
  - `103` `running`
  - `104` `running`
  - `102`, `201`, `202`, `203` und `204` `stopped`

## 2026-07-08 Bitcoin-Konzept umgesetzt

- `203 vm-bitcoin-node` und `204 vm-bitcoin-service` wurden fuer Abschnitt 06 erneut nur offline auf dem Host vorbereitet und anschliessend ueber kurze Validator-Boots abgearbeitet.
- `203` erhielt einen strikt dateibasierten Watch-only-/Referenzpfad:
  - `/srv/bitcoin-sim/node/reference`
  - `/srv/bitcoin-sim/node/export`
  - `/srv/bitcoin-sim/node/validation`
  - Dummy-Deskriptor, Dummy-UTXO-Referenz, Dummy-Fee-Policy und `watchonly-bundle.json`
- `204` erhielt einen strikt getrennten Hot-Service-Simulationspfad:
  - dedizierter System-User `btcpayout`
  - `/srv/bitcoin-sim/service/inbox/requests`
  - `/srv/bitcoin-sim/service/reference`
  - `/srv/bitcoin-sim/service/work/unsigned-psbt`
  - `/srv/bitcoin-sim/service/import/signed`
  - `/srv/bitcoin-sim/service/outbox/receipts`
  - `/srv/bitcoin-sim/service/archive`
  - `/srv/bitcoin-sim/service/validation`
- Der simulierte Offline-Signer blieb bewusst ausserhalb der Gaeste und wurde nur ueber den root-only Hostpfad `/root/ailab-runtime/bitcoin-sim-offline` abgebildet.
- Praktisch validierter Dummy-PSBT-Ablauf:
  - `203` exportiert Watch-only-Bundle
  - Host uebergibt Bundle an `204`
  - `204` Phase 1 erzeugt `payout-0001-unsigned.psbt.json`
  - Host erzeugt root-only `payout-0001-signed.psbt.json`
  - `204` Phase 2 importiert dieses Dummy-Artefakt und schreibt `payout-0001-broadcast.json`
- Listener- und Prozess-Validatoren bestaetigen fuer `203` und `204`:
  - keine offenen Bitcoin-Ports auf `8332`, `8333`, `18332`, `18333`, `18443`, `18444`, `50001`, `50002`, `50011`, `50012`, `3000`, `3002`
  - keine laufenden `bitcoind`-, `electrs`-, `electrumx`-, `fulcrum`- oder aehnlichen Prozesse
- Rechte-Validatoren bestaetigen:
  - `203` Referenz-/Exportpfade `750 root:root`, Artefakte `640 root:root`
  - `204` Servicepfade mit `root:btcpayout`, Schreibpfade `770`, Import-/Referenzpfade `750`, Archiv `700 root:root`
  - root-only Host-Handoff-Dateien `600 root:root`
- Erste Nachlaeufe:
  - Der erste Phase-1-Lauf von `204` scheiterte, weil die kleine TCG-VM den Markerpfad vor dem urspruenglichen Wait-Fenster nicht erreichte.
  - Die Journalanalyse auf `204` zeigte anschliessend einen problematischen `/boot/efi`-Mountpfad, der in dieser Testbasis vorzeitig in einen schlechten Bootzustand fuehrte.
  - Das IaC wurde daraufhin reproduzierbar gehaertet:
    - laengeres Wait-Fenster fuer `204`
    - `/etc/fstab` auf `203` und `204` fuer `/boot/efi` mit `nofail,x-systemd.device-timeout=1s`
- Der finale Endlauf war erfolgreich; `203` und `204` enden wieder `stopped`, und fuer beide existiert jetzt der Snapshot `post-bitcoin-sim`.

## 2026-07-08 Fehleranalyse dokumentiert

- Fuer Abschnitt 07 wurden keine neuen Live-Aenderungen auf `ailab2` vorgenommen.
- Analysiert wurden ausschliesslich die realen Artefakte aus:
  - `/root/ailab2-iac/section-03-config`
  - `/root/ailab2-iac/section-04-network-tor`
  - `/root/ailab2-iac/section-05-backup-monitoring`
  - `/root/ailab2-iac/section-06-bitcoin-simulation`
  - den laufenden Doku-Dateien unter `outputs/`
- Das Ergebnis ist in `outputs/fehleranalyse-benchmark.md` als priorisierter Benchmark festgehalten.
- Wesentliche Befundgruppen:
  - P2: kurzzeitige Admin-Metadaten im IaC-Pfad, Borg-/`ntfy`-/Bind-/Routing-Bootstrapfehler, TCG-/EFI-Bootblocker auf `204`
  - P3: `vmbr90`-Validator-False-Negatives auf `203`, Resume-/Loop-Fragilitaet in Abschnitt 04, falsche `torrc.d`-Annahme
- Der Abschnitt blieb bewusst read-only bezueglich `ailab2`; aktualisiert wurden nur die Doku-Dateien im Workspace.

## Naechster geplanter Abschnitt

- abschliessender Self-Audit und Abschlussbericht
