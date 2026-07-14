# Validator Notes

## Baseline-Validator 2026-07-07

### Ziel

- Nachweis des unveraenderten Startzustands vor jeder Implementierung

### Durchgefuehrte Pruefungen

- SSH-Login auf `ailab2`
- `hostnamectl`
- `pveversion -v`
- `ip -br addr`
- `ip route`
- `cat /etc/network/interfaces`
- `pve-firewall status`
- `ss -tulpn`
- `qm list`
- `pct list`
- `pvesm status`
- `lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS`
- `free -h`
- `df -hT`
- `cat /etc/pve/datacenter.cfg`

### Ergebnis

- Bestandsaufnahme erfolgreich
- Noch keine Aenderung am Live-Zustand durchgefuehrt
- Keine bestehenden Gastsysteme gefunden
- Management-Dienste sind bereits erreichbar und muessen spaeter eingeschraenkt werden
- Baseline ist ausreichend, um den Architekturabschnitt fundiert zu planen

### Offene Validierungen

- Nach jedem freigegebenen Abschnitt:
  - Dateipruefung der geaenderten Artefakte
  - Live-Pruefung der betroffenen Dienste
  - Abgleich gegen Risiko- und Entscheidungsdokumentation

## Dokumentations-Validator 2026-07-07 Architekturabschnitt

### Ziel

- Nachweis, dass der freigegebene Architekturabschnitt vollstaendig in den Doku-Dateien abgebildet ist
- Nachweis, dass keine Live-Aenderung an `ailab2` stattgefunden hat

### Gepruefte Dateien

- `outputs/master-plan.md`
- `outputs/decision-log.md`
- `outputs/risk-register.md`
- `outputs/bitcoin-simulation.md`
- `outputs/implementation-log.md`

### Verwendete Pruefmethoden

- `Get-Content` fuer Volltextsichtung
- `Select-String` fuer gezielte Nachweise auf:
  - operator-only-Regeln
  - Secrets- und Backup-Klassen
  - Deny-by-default-Kommunikationsmatrix
  - Bitcoin-Sperrliste mit `xprv` und `wallet.dat`

### Ergebnis

- Erfolgreich
- Die Architekturtrennung zwischen Management, Infrastruktur, Anwendungsdiensten, Monitoring, Backup und Bitcoin-Simulation ist dokumentiert.
- Schutzbedarf, Zugriffspfade, Secrets-Klasse und Backup-/Restore-Klasse sind pro Bereich vorhanden.
- Die Deny-by-default-Kommunikationsmatrix ist vorhanden.
- Proxmox-Web-UI ist explizit als operator-only und nicht regulaer veroeffentlicht festgehalten.
- Grafana, Alertmanager und `ntfy` sind explizit als operator-only festgehalten.
- Monitoring-Endpunkte sind explizit nicht als allgemeine Nutzerdienste markiert.
- Die Bitcoin-Dummy-only-Regel auf `ailab2` ist explizit dokumentiert.
- Im Validator wurden keine SSH- oder sonstigen Live-Aktionen gegen `ailab2` ausgefuehrt.

### Offene Restpunkte

- Technische Umsetzung der Architektur ist noch nicht gestartet.
- Naechster freigabepflichtiger Abschnitt ist `Services`.

## Live-Validator 2026-07-07 Gastgrundlagen / Provisionierung

### Ziel

- Nachweis, dass die Provisionierungsbasis fuer alle geplanten Gastrollen auf `ailab2` angelegt wurde
- Nachweis, dass Bridges, Storage-Ziele, Gasttypen, onboot-Status und Baseline-Snapshots mit der Doku uebereinstimmen

### Durchgefuehrte Pruefungen

- Vorab-Ressourcenpruefung:
  - `free -h`
  - `df -hT`
  - `pvesm status`
  - `qm list`
  - `pct list`
- Host-Netz:
  - Backup von `/etc/network/interfaces`
  - neue Bridges `vmbr10` bis `vmbr50` angelegt
  - `ip -br link`
- Basisartefakte:
  - `pveam update`
  - `pveam download local debian-13-standard_13.1-2_amd64.tar.zst`
  - lokaler `sha512sum` des LXC-Templates
  - Download des gepinnten Debian-Cloud-Images
  - `sha512sum -c` gegen `SHA512SUMS`
  - Pruefung auf `SHA512SUMS.sign` am gepinnten Cloud-Pfad
- Gastobjekte:
  - `pct create` fuer `101` bis `104`
  - `qm create`/`qm importdisk`/`qm template` fuer `9000`
  - `qm clone` fuer `201` bis `204`
  - `qm resize` fuer die dokumentierten Sollgroessen der VM-Disks
  - `qm set --kvm 0` fuer die vier VMs als lokale Nested-KVM-Ausweichstrategie
- Baseline-Validierung:
  - kurzer Start aller acht Gaeste
  - Stop bzw. Shutdown in den Zustand `stopped`
  - Snapshot-Anlage `post-provision-base`
  - Stichproben ueber `qm config`, `pct config`, `qm listsnapshot`, `pct listsnapshot`, `lvs -a`

### Ergebnis

- Erfolgreich mit dokumentierter Abweichung.
- Die zusaetzlichen Bridges `vmbr10`, `vmbr20`, `vmbr30`, `vmbr40` und `vmbr50` existieren auf dem Host.
- Vier LXCs und vier VMs entsprechend der dokumentierten Zonenstruktur wurden angelegt.
- Alle acht Gastrollen enden nach diesem Abschnitt im Soll-Zustand `stopped`.
- Alle acht Gastrollen besitzen den Snapshot `post-provision-base`.
- `onboot` ist fuer alle acht Gastrollen deaktiviert.
- Die LXC-Gaeste sind unprivileged und fuehren die deaktivierten Zusatzfeatures explizit in ihrer Konfiguration.
- Die VM-Disks entsprechen jetzt den dokumentierten Sollgroessen `6G`, `6G`, `8G` und `4G`.
- Die Provisionierungsbasis wurde ohne App-Rollout, ohne Onion-Veröffentlichung, ohne produktive App-Firewall-Feinkonfiguration und ohne produktive Secrets angelegt.
- Bitcoin bleibt in diesem Abschnitt dummy-only; es wurden keine Wallet-Artefakte materialisiert.

### Dokumentierte Abweichungen und Befunde

- Fuer das gepinnte Debian-Cloud-Image war am konkreten Cloud-Pfad keine `SHA512SUMS.sign` verfuegbar; umgesetzt wurde daher die Hash-Pruefung gegen `SHA512SUMS` und eine explizite Restrisiko-Dokumentation.
- In der VirtualBox-basierten Test-VM stand kein nutzbares Nested-KVM zur Verfuegung. Die VM-Boot-Pruefung wurde deshalb mit `kvm=0` per Softwareemulation validiert.
- Thin-LVM meldet wegen der Baseline-Snapshots eine virtuelle Summenwarnung. Der reale Poolverbrauch lag zum Zeitpunkt der Validierung jedoch nur bei ca. `12.25%`.

### Offene Restpunkte

- Die Provisionierungsbasis ist vorhanden, aber die Dienste selbst sind noch nicht ausgerollt.
- Interne Bridges tragen absichtlich keine Host-IP und keine Routing-Logik; die eigentliche Netz- und Tor-Umsetzung folgt spaeter.
- Naechster fachlicher Detailabschnitt ist `Konfiguration`.

## Live-Validator 2026-07-07 Konfiguration

### Ziel

- Nachweis, dass die Konfigurationsbasis fuer `102`, `103`, `104`, `201`, `202`, `203` und `204` praktisch umgesetzt wurde
- Nachweis, dass der temporare Paketversorgungspfad ueber `vmbr90` nur den APT-Proxy bereitstellt
- Nachweis, dass die Host-Ports `22`, `111`, `8006` und `3128` aus den temporaer angebundenen Gaesten nicht erreichbar sind
- Nachweis des vollstaendigen Rueckbaus von `vmbr90`, `apt-cacher-ng`, `ailab_vmbr90` und den temporaeren NICs

### Durchgefuehrte Pruefungen

- Vorab-Precheck:
  - `pct status 101` musste `stopped` bleiben
  - keine vorhandene `vmbr90`
  - keine vorhandene `ailab_vmbr90`
  - keine temporaeren `net9`-/`net1`-Adapter an den Zielgaesten
- Host-seitiger Temp-Pfad:
  - `vmbr90` auf `172.31.90.1/24`
  - `apt-cacher-ng` nur auf `172.31.90.1:3142`
  - `nft list table inet ailab_vmbr90`
  - Regelmodell: nur `tcp/3142` zu `172.31.90.1`, sonst Drop fuer Input/Forward von `vmbr90`
- LXC-Basis fuer `102`, `103`, `104`:
  - temp. `net9`
  - `apt-get update`
  - `apt-get -y --with-new-pkgs upgrade`
  - Dateipruefungen auf `/etc/ailab`, `journald`-Limits, Rollenpfade und `section-03-config.done`
- VM-Basis fuer `201`, `202`, `203`, `204`:
  - Offline-Chroot fuer die Basiskonfiguration
  - kurze Bootphase nur fuer den `vmbr90`-Validator
  - Dateipruefungen auf `/etc/ailab`, `qemu-guest-agent`, `/srv`-Pfade und `section-03-config.done`
- Pro Gast gepruefte Artefakte:
  - Paketmanifeste unter `/root/ailab2-iac/section-03-config/manifests`
  - Port-Checks unter `/root/ailab2-iac/section-03-config/port-checks`
- Port-Freigaben waehrend des Temp-Pfads:
  - `102-ct-edge-proxy-vmbr90.txt`
  - `103-ct-monitoring-vmbr90.txt`
  - `104-ct-backup-vmbr90.txt`
  - `201-vm-apps-core-vmbr90.txt`
  - `202-vm-apps-extended-vmbr90.txt`
  - `203-vm-bitcoin-node-vmbr90.txt`
  - `204-vm-bitcoin-service-vmbr90.txt`
- Host-Zustand nach Rueckbau:
  - `host-bridges-after-cleanup.txt`
  - `host-ports-after-cleanup.txt`
  - `nft-tables-after-cleanup.txt`
  - `host-proxy-package-state.txt`
  - finale `pct config`/`qm config`
  - Snapshotlisten `post-config-base`

### Ergebnis

- Erfolgreich mit dokumentierten Abweichungen.
- `101 ct-tor-gateway` blieb im ganzen Abschnitt unveraendert und gestoppt.
- Die Baseline umfasste echte Paketupdates und nicht nur `apt update`.
- Fuer alle sieben geaenderten Gaeste liegen Paket- und Versionsmanifeste vor.
- Alle sieben `vmbr90`-Portchecks zeigen den geforderten Nachweis:
  - `tcp/3142=open`
  - `tcp/22=blocked`
  - `tcp/111=blocked`
  - `tcp/8006=blocked`
  - `tcp/3128=blocked`
- Damit ist explizit belegt, dass ueber `vmbr90` nur der APT-Proxy erreichbar war und die Management-Ports des Hosts fuer die temporaer angebundenen Gaeste gesperrt blieben.
- Die Datei `host-ports-after-cleanup.txt` zeigt weiterhin die hostseitig global offenen Proxmox-/Management-Ports; das ist fuer diesen Abschnitt erwartbar und getrennt von der erfolgreichen `vmbr90`-Isolation zu lesen.
- Nach Rueckbau gilt:
  - keine Bridge `vmbr90`
  - kein Listener auf `172.31.90.1:3142`
  - keine Tabelle `ailab_vmbr90`
  - keine temporaeren `net9`-/`net1`-Adapter mehr an den Zielgaesten
  - alle acht Gaeste `stopped`
- Alle acht Gaeste besitzen nun `post-config-base`.

### Dokumentierte Abweichungen und Befunde

- Die vier VMs wurden nicht ueber einen laengeren Online-Provisionierungspfad konfiguriert, sondern per Offline-Chroot plus kurzem Validator-Boot. Grund ist die Testumgebung mit `kvm=0` und zeitweise unzuverlaessiger QGA-/Cloud-Init-Interaktion unter Softwareemulation.
- `203 vm-bitcoin-node` erzeugte im ersten Nachlauf zunaechst `tcp/3142=blocked`. Der Validator wurde daraufhin mit `network-online.target`, `systemd-networkd-wait-online.service` und Proxy-Retry gehaertet; der erneute Lauf lieferte den korrekten Nachweis `tcp/3142=open`.
- Nach dem finalen `203`-Lauf blieb ein einzelner Loop-Handle aus dem Offline-Mounting offen. Er wurde vor Abschluss manuell geloest; danach verblieben keine offenen Loop-Devices aus diesem Abschnitt.

### Offene Restpunkte

- Keine App-Runtimes, Datenbanken, Webserver oder Onion-Veröffentlichungen wurden in diesem Abschnitt ausgerollt.
- Die globale Host-Exponierung auf `22`, `111`, `8006` und `3128` besteht weiterhin und wird erst im Abschnitt `Netzwerk / Tor` bzw. spaeteren Hardening-Schritten verengt.
- Naechster fachlicher Detailabschnitt ist `Netzwerk / Tor`.

## Live-Validator 2026-07-07 Netzwerk / Tor

### Ziel

- Nachweis, dass die dokumentierten Zonen-Gateways, Host-Firewallregeln und Admin-Pfade praktisch umgesetzt wurden
- Nachweis, dass die Proxmox-Web-UI operator-only bleibt und kein regulaerer Nutzdienst ist
- Nachweis, dass der Admin-SSH-Pfad ueber `101 ct-tor-gateway` und den Onion-Service funktioniert, ohne die Host-Management-Ports breit freizugeben
- Nachweis, dass die internen Zonen `102`, `103`, `104`, `201`, `202`, `203` und `204` ihre jeweiligen Host-Gateway-Ports `22`, `111`, `8006` und `3128` nicht erreichen koennen

### Durchgefuehrte Pruefungen

- Host-seitige Netz- und Firewallpruefung:
  - `/etc/network/interfaces`
  - `ip -4 addr`
  - `ip route`
  - `sysctl net.ipv4.ip_forward`
  - `nft list ruleset`
  - `ss -ltnp '( sport = :22 or sport = :111 or sport = :8006 or sport = :3128 )'`
- Operator-Pfad nach Host-Hardening:
  - lokales `curl -k -I https://127.0.0.1:8012/`
  - lokaler SSH-Login mit fixiertem Host-Key ueber `127.0.0.1:2225`
- `101 ct-tor-gateway`:
  - finale `pct config`
  - `101-ct-tor-gateway-admin.txt`
  - `101-admin-ssh-onion.txt`
  - `101-tor-service.txt`
  - `101-ipv4-final.txt`
  - `101-routes-final.txt`
- Interne Zonen:
  - `102-ct-edge-proxy-host-ports.txt`
  - `103-ct-monitoring-host-ports.txt`
  - `104-ct-backup-host-ports.txt`
  - `201-vm-apps-core-host-ports.txt`
  - `202-vm-apps-extended-host-ports.txt`
  - `203-vm-bitcoin-node-host-ports.txt`
  - `204-vm-bitcoin-service-host-ports.txt`
- Endzustand:
  - `pct list`
  - `qm list`
  - `pct listsnapshot`
  - `qm listsnapshot`
  - `host-ports-final.txt`
  - `host-routes-final.txt`
  - `host-nft-ruleset-final.txt`
  - Pruefung auf entfernten `rollback-guard.pid`

### Ergebnis

- Erfolgreich mit dokumentierten technischen Nachlaeufen.
- Der lokale Operator-Pfad blieb intakt:
  - `https://127.0.0.1:8012/` antwortet weiterhin ueber den bestehenden Pfad
  - SSH auf `127.0.0.1:2225` liefert weiterhin den Host `ailab2`
- Das finale Host-Regelwerk entspricht dem operator-only-Modell:
  - `vmbr0` akzeptiert nur `10.0.2.2 -> tcp/22,8006`
  - `vmbr10` akzeptiert nur `10.10.10.10 -> tcp/22`
  - `input` und `forward` sind sonst `drop`/`reject`
- `101 ct-tor-gateway` liefert den beabsichtigten Admin-Pfad:
  - `tcp/10.10.10.1:22=open`
  - `tcp/10.10.10.1:111=blocked`
  - `tcp/10.10.10.1:8006=blocked`
  - `tcp/10.10.10.1:3128=blocked`
  - `tcp/10.0.2.15:22=blocked`
  - `tcp/10.0.2.15:111=blocked`
  - `tcp/10.0.2.15:8006=blocked`
  - `tcp/10.0.2.15:3128=blocked`
  - `onion/tcp22=open`
- Die Monitoring-, Backup-, App- und Bitcoin-Zonen erreichen ihre jeweiligen Host-Gateway-Ports `22`, `111`, `8006` und `3128` nicht.
- Fuer `101`, `102`, `103`, `104`, `201`, `202`, `203` und `204` existiert der Snapshot `post-network-tor-base`.
- Endzustand des Abschnitts:
  - `101` laufend
  - `102`, `103`, `104`, `201`, `202`, `203` und `204` gestoppt
  - `rollback-guard.pid` entfernt
- Bitcoin bleibt auch nach diesem Abschnitt strikt dummy-only; es wurden keine Wallet-, Seed- oder Schluesselartefakte angelegt.

### Dokumentierte Abweichungen und Befunde

- Die erste 101-Konfiguration mit DHCP auf `vmbr0` fuehrte zu instabiler Operator-Erreichbarkeit; die CT wurde deshalb auf die statische Adresse `10.0.2.101/24` umgestellt und danach erneut validiert.
- Das Debian-13-Tor-Basisimage in `101` lud die geplante `torrc.d`-Drop-in-Datei nicht; die funktionierende Hidden-Service-Konfiguration wurde deshalb direkt in `/etc/tor/torrc` verankert.
- Der erste Abschnitt-04-Finalizer musste wegen `kvm=0`-/TCG-Timing, alter `vmbr90`-Validatorreste in `201/202` und verzoegerter `loopXp1`-Bereitstellung bei `203` gehaertet und mehrfach fortgesetzt werden; der Endlauf `run-20260707T173925Z-resume3.log` ist erfolgreich.
- Die Snapshot-Tasks meldeten nur bekannte Thin-LVM-Warnungen zur virtuellen Summengroesse; alle Snapshot-Objekte `post-network-tor-base` wurden dennoch erfolgreich angelegt.

### Offene Restpunkte

- Es existiert bisher nur der operator-only Admin-Onion fuer SSH; allgemeine Service-Onions wurden bewusst noch nicht veroeffentlicht.
- Die Host-Daemons `rpcbind` auf `111/tcp` und `spiceproxy` auf `3128/tcp` lauschen weiterhin lokal auf dem Host, sind aber aus den Zonenpfaden durch `nftables` blockiert und muessen spaeter separat auf Notwendigkeit geprueft werden.
- Naechster fachlicher Detailabschnitt ist `Backup / Monitoring`.

## Live-Validator 2026-07-07 Admin-Tor-Haertung / zentrale Host-Schutzschicht

### Ziel

- Nachweis, dass der Admin-Onion nur noch fuer explizit autorisierte Clients nutzbar ist
- Nachweis, dass nach dem Validator genau ein testweise autorisierter Operator-Client uebrig bleibt und temporaere Testartefakte entfernt sind
- Nachweis, dass `nftables` die einzige wirksame Host-Schutzschicht ist und `pve-firewall` nicht mehr parallel wirkt
- Nachweis, dass die effektive Tor-Konfiguration in `101` eindeutig und driftarm ist

### Durchgefuehrte Pruefungen

- Host-seitig:
  - frische SSH-Sitzungen ueber den bestehenden lokalen Operator-Pfad
  - `systemctl is-enabled nftables`
  - `systemctl is-active nftables`
  - `systemctl is-enabled pve-firewall`
  - `systemctl is-active pve-firewall`
  - `pve-firewall status`
  - `nft list table inet ailab`
  - `sshd -T | egrep 'permitrootlogin|passwordauthentication|pubkeyauthentication|authenticationmethods|kbdinteractiveauthentication'`
  - Pruefung des root-only-Runtimepfads `/root/ailab-runtime/admin-onion-operator`
- `101 ct-tor-gateway`:
  - `systemctl is-active tor@default`
  - Nachweis, dass `/etc/tor/torrc.d/10-ailab-admin-ssh.conf` fehlt
  - Nachweis, dass es nur eine effektive `HiddenServiceDir /var/lib/tor/ssh-admin-onion`-Definition unter `/etc/tor` gibt
  - Pruefung der Datei `/var/lib/tor/ssh-admin-onion/authorized_clients/operator-1.auth`
  - erneuter Portcheck `10.10.10.1:{22,111,8006,3128}` und `10.0.2.15:{22,111,8006,3128}`
- Tor-Client-Auth-Nachweis:
  - temporaerer autorisierter Tor-Client in `101` mit root-only Auth-Kopie
  - temporaerer unautorisierter Tor-Client in `101` ohne Client-Auth
  - beide Clients warten jeweils bis `Bootstrapped 100% (done): Done`
  - danach TCP-Test gegen den Admin-Onion auf `22/tcp`
- Rueckbau- und Doku-Pruefung:
  - keine verbleibenden Temp-Verzeichnisse `/root/tor-client-check`, `/root/tor-client-auth-check`, `/root/tor-client-unauth-check`
  - keine verbliebenen Host-Tempdirs `ailab-auth-validate.*`
  - Suche nach konkreter Onion-Adresse in `outputs`
  - Suche nach konkreter Onion-Adresse und nach dem `.auth_private`-Inhalt in `/root/ailab2-iac`

### Ergebnis

- Erfolgreich.
- Die zentrale Host-Schutzschicht ist jetzt eindeutig:
  - `nftables`: `enabled`, `active`
  - `pve-firewall`: `disabled`, `inactive`
  - `pve-firewall status`: `disabled/stopped`
- Das effektive Host-Regelwerk bleibt unveraendert eng:
  - `vmbr0`: nur `10.0.2.2 -> tcp/22,8006`
  - `vmbr10`: nur `10.10.10.10 -> tcp/22`
  - aus `101` bleiben `10.10.10.1:111/8006/3128` sowie `10.0.2.15:22/111/8006/3128` `blocked`
- Die Tor-Konfiguration in `101` ist jetzt eindeutig:
  - `tor@default` ist `active`
  - die fruehere Drop-in-Datei fehlt
  - genau eine effektive Hidden-Service-Definition fuer `/var/lib/tor/ssh-admin-onion`
  - genau eine service-seitige Autorisierungsdatei `operator-1.auth` mit `0600 debian-tor:debian-tor`
- Der Admin-Onion ist auf den kleinen Betreiberkreis verengt:
  - autorisierter Tor-Client: `open`
  - unautorisierter Tor-Client nach vollem Bootstrap: `blocked`
  - der unautorisierte Tor-Client meldete im Log: `Fail to decrypt descriptor for requested onion address. It is likely requiring client authorization.`
- Nach dem Rueckbau verbleibt genau ein Test-Operator-Artefakt:
  - `operator-1.auth_private`
  - `0600 root:root`
  - keine zusaetzlichen Temp-Tor-Clients oder Host-Tempdirs mehr vorhanden
- Die konkrete Onion-Adresse und der `.auth_private`-Inhalt liegen nicht in `outputs`; im IaC-Pfad liegen weder Onion-Adresse noch `.auth_private`-Inhalt mehr vor.

### Dokumentierte Abweichungen und Befunde

- Zwei fruehere IaC-Validatorartefakte aus Abschnitt 04 enthielten noch die konkrete Admin-Onion-Adresse. Sie wurden in diesem Schritt redigiert, damit der IaC-Pfad keine laufzeitnahe Admin-Adresse mehr traegt.
- Der lokale Host-SSH-Pfad blieb fuer diesen Run bewusst mit unveraenderter Host-Authentisierung bestehen; das ist keine vergessene Nacharbeit, sondern eine Scope-Grenze dieses Runs.

### Offene Restpunkte

- Der lokale Host-SSH-Pfad arbeitet weiterhin mit `PermitRootLogin yes`, `PasswordAuthentication yes` und `authenticationmethods any`; das ist als verbleibendes Scope-Restrisiko zu lesen und nicht als vollstaendig geloestes Host-SSH-Hardening.
- Es verbleibt bewusst nur ein root-only Test-Operator-Artefakt auf `ailab2`; fuer einen spaeteren Produktivtransfer muesste ein echter Operator-Client ausserhalb dieses Hosts materialisiert und sicher verteilt werden.
- Naechster fachlicher Detailabschnitt bleibt `Backup / Monitoring`.

## Live-Validator 2026-07-07 Backup / Monitoring

### Ziel

- Nachweis der operator-only Monitoring-/Backup-Basis auf `ailab2`
- Nachweis, dass `vmbr90` waehrend der Paketversorgung nur den APT-Proxy bereitstellte und danach vollstaendig entfernt wurde
- Nachweis, dass Host-, `101`- und `104`-Exporter an den geforderten Zonenadressen binden
- Nachweis, dass `101` nur sanitisierte Rebuild-Artefakte und keine Hidden-Service-Identitaet im Backup traegt
- Nachweis, dass der Host-zu-`104`-Pfad auf `borgrepo` plus `borg serve` begrenzt ist
- Nachweis eines risikolosen Smoke-Restores auf dem finalen Borg-Archivstand

### Durchgefuehrte Pruefungen

- Host:
  - `systemctl is-enabled` und `systemctl is-active` fuer `nftables`, `pve-firewall`, `prometheus-node-exporter`, `ailab-backup.timer` und `ailab-ssh-auth-metrics.timer`
  - `ss -ltnp` fuer Listener-Nachweise
  - `sysctl net.ipv4.ip_forward`
  - `stat` auf `/root/ailab-runtime/borg-host-to-104/*`
  - Borg-Archivliste und Smoke-Restore in ein temporaeres Host-Verzeichnis
- `101 ct-tor-gateway`:
  - `systemctl is-active prometheus-node-exporter`
  - `ss -ltnp`
  - `ip route`
  - persistente `/etc/network/interfaces` mit Rueckroute `10.30.30.0/24 via 10.10.10.1 dev eth1`
- `103 ct-monitoring`:
  - `systemctl is-active prometheus prometheus-alertmanager prometheus-blackbox-exporter prometheus-node-exporter ntfy`
  - `ss -ltnp`
  - HTTP-Ready-Checks fuer Prometheus und Alertmanager
  - Blackbox-Probe gegen `http://10.30.30.103:2586/`
  - Prometheus-Targets-API mit sechs aktiven Targets
  - Zonenkonnektivitaet von `103`:
    - `10.30.30.1:9100`
    - `10.10.10.10:9100`
    - `10.40.40.104:9100`
    - `10.30.30.1:{22,111,8006,3128}`
- `104 ct-backup`:
  - `systemctl is-active ssh prometheus-node-exporter`
  - `sshd -T -C user=borgrepo,addr=10.40.40.1,host=ct-backup`
  - Rechte auf `/var/lib/borgrepo`, `.ssh`, `authorized_keys` und `/srv/backup/repos/host`
  - SSH-Test auf `borgrepo` ohne Shell
- temp. Paketpfad:
  - `port-checks/103-vmbr90.txt`
  - `port-checks/104-vmbr90.txt`
  - Nachweis des fehlenden Devices `vmbr90`

### Ergebnis

- Erfolgreich, nach mehreren dokumentierten technischen Nachlaeufen.
- Host-Schutz- und Monitoring-Basis:
  - `nftables`: `enabled`, `active`
  - `pve-firewall`: `disabled`, `inactive`
  - Host-Exporter: `10.30.30.1:9100`
  - Host-Backup-Timer und Host-SSH-Metrik-Timer: `enabled`, `active`
- Monitoring-CT `103`:
  - `prometheus`, `prometheus-alertmanager`, `prometheus-blackbox-exporter`, `prometheus-node-exporter` und `ntfy` sind final alle `active`
  - Listener nur auf `10.30.30.103:9090`, `:9093`, `:9094`, `:9100`, `:9115` und `:2586`
  - alle sechs aktiven Prometheus-Targets sind final `health=up`
- Exporter-/Zonenpfade:
  - `103 -> 10.30.30.1:9100 = open`
  - `103 -> 10.10.10.10:9100 = open`
  - `103 -> 10.40.40.104:9100 = open`
  - `103 -> 10.30.30.1:{22,111,8006,3128} = blocked`
  - damit bleibt `8006/tcp` aus der Monitoring-Zone explizit unerreichbar
- `101 ct-tor-gateway`:
  - Exporter final auf `10.10.10.10:9100`
  - Rueckroute zur Monitoring-Zone final aktiv und persistent dokumentiert
- `104 ct-backup`:
  - Exporter final auf `10.40.40.104:9100`
  - `borgrepo` ist auf `AuthenticationMethods publickey`, `ForceCommand /usr/bin/borg serve --restrict-to-path /srv/backup/repos/host`, `PermitTTY no`, `AllowTcpForwarding no`, `AllowAgentForwarding no`, `AllowStreamLocalForwarding no` und `PasswordAuthentication no` verengt
  - der Host-SSH-Test gegen `borgrepo` endet in Borg-Usage statt Shell
- Backup-Inhalt:
  - final validiertes Archiv: `ailab2-20260707T212412Z`
  - Borg-Repository enthaelt zwei Archive; der letzte Lauf repraesentiert den bereinigten Endzustand
  - `current-staging-files.txt` zeigt nur sanitisierte `101`-Artefakte, CT-Konfigurationen, Paketmanifeste und Host-Strukturartefakte
  - `borg-smoke-restore-101-configs.txt` enthaelt `etc/tor/torrc`, `etc/network/interfaces`, `etc/default/prometheus-node-exporter` und relevante Systemd-Overrides, aber kein `var/lib/tor/ssh-admin-onion`
- Temp-Paketpfad:
  - `103-vmbr90.txt` und `104-vmbr90.txt` zeigen `tcp/3142=open` und `tcp/22`, `tcp/111`, `tcp/8006`, `tcp/3128` als `blocked`
  - `vmbr90-link-state.txt` bestaetigt den vollstaendigen Rueckbau: `Device "vmbr90" does not exist.`
- Abschnitts-Endzustand:
  - `101`, `103` und `104` `running`
  - `102`, `201`, `202`, `203` und `204` `stopped`

### Dokumentierte Abweichungen und Befunde

- Der erste Backup-Lauf scheiterte an fehlendem `known_hosts` fuer `10.40.40.104`; danach wurden `known_hosts` und root-only-Rechte im Borg-Runtimepfad nachgezogen.
- `ntfy` startete zunaechst nicht, weil die Debian-Paketverzeichnisse `/var/cache/ntfy` und `/var/lib/ntfy` in der CT fehlten; sie wurden mit `_ntfy:_ntfy` nachgezogen.
- Nach den CT-Neustarts scheiterten mehrere bind-sensitive Dienste zunaechst an noch nicht gesetzten Zonenadressen; dafuer wurden `ailab-wait-ip.sh` und passende Systemd-Drop-ins eingefuehrt.
- `101` beantwortete Monitoring-Anfragen anfangs ueber den falschen Default-Pfad `eth0`; die persistente Rueckroute ueber `eth1` wurde danach nachgezogen und erneut validiert.
- Der erste erfolgreiche Borg-Archivstand entstand noch vor dem finalen Temp-Pfad-Cleanup; deshalb wurde der Backup-Lauf bewusst erneut angestossen, bis `latest-borg-archive.txt` auf den bereinigten Endzustand zeigte.

### Offene Restpunkte

- Das Borg-Repository liegt weiterhin auf demselben Testhost und ersetzt keine spaetere Off-Host- oder Wechselmedium-Strategie.
- Monitoring-Oberflaechen bleiben in diesem Abschnitt interne operator-only-Pfade; eine spaetere dedizierte Auth-/Onion-Schicht fuer mobile Operator-Nutzung ist noch offen.
- Naechster fachlicher Detailabschnitt ist `Bitcoin-Konzept`.

## Live-Validator 2026-07-08 Bitcoin-Konzept

### Ziel

- Nachweis, dass der Bitcoin-Teil auf `ailab2` strikt dummy-only bleibt
- Nachweis, dass auf `203` und `204` keine Bitcoin-Listener offen sind
- Nachweis, dass die Dateirechte fuer Watch-only-, Service- und Host-Handoff-Pfade restriktiv gesetzt sind
- Nachweis eines kompletten Dummy-PSBT-Ablaufs mit klar getrennten Rollen

### Durchgefuehrte Pruefungen

- `203 vm-bitcoin-node`:
  - Auslesen von `203-node-bitcoin-listener-check.txt`, `203-node-bitcoin-process-check.txt`, `203-node-forbidden-artifacts.txt`, `203-node-permissions.txt` und `203-node-role-separation.txt`
  - Extraktion von `watchonly-bundle.json`
- `204 vm-bitcoin-service`:
  - Phase 1:
    - `204-service-phase1-workflow-state.txt`
    - `204-service-phase1-bitcoin-listener-check.txt`
    - `204-service-phase1-bitcoin-process-check.txt`
    - `204-service-phase1-forbidden-artifacts.txt`
    - `204-service-phase1-permissions.txt`
  - Phase 2:
    - `204-service-phase2-workflow-state.txt`
    - `204-service-phase2-bitcoin-listener-check.txt`
    - `204-service-phase2-bitcoin-process-check.txt`
    - `204-service-phase2-forbidden-artifacts.txt`
    - `204-service-phase2-permissions.txt`
    - `204-service-phase2-role-separation.txt`
    - `204-service-broadcast-receipt.json`
- Host:
  - Rechtepruefung fuer `/root/ailab-runtime/bitcoin-sim-offline/*`
  - Status- und Snapshot-Pruefung fuer `203` und `204`
  - Journalpruefung auf `204` ueber das persistente Gastjournal

### Ergebnis

- Erfolgreich, nach dokumentierten Nachlaeufen auf `204`.
- Dummy-only-Regel:
  - keine echten Seeds, keine echten `xprv`, keine echten `wallet.dat`, keine produktiven Private Keys und keine produktiven API-Schluessel angelegt
  - `wallet_dat=absent`, `seed_files=absent`, `xprv_files=absent` auf `203` sowie in Phase 1 und Phase 2 auf `204`
- Keine Bitcoin-Listener:
  - `203` und `204` melden fuer `8332`, `8333`, `18332`, `18333`, `18443`, `18444`, `50001`, `50002`, `50011`, `50012`, `3000`, `3002` jeweils `absent`
  - `bitcoin_daemons=absent` auf `203` sowie in beiden `204`-Phasen
- Rollen und Workflow:
  - `203` exportiert nur Watch-only-Bundle und speichert keine unsigned oder signed PSBTs
  - `204` Phase 1: `request_present=yes`, `reference_present=yes`, `unsigned_present=yes`, `signed_present=no`, `receipt_present=no`
  - `204` Phase 2: `request_present=yes`, `reference_present=yes`, `unsigned_present=yes`, `signed_present=yes`, `receipt_present=yes`
  - root-only Host-Handoff bestaetigt:
    - Watch-only-Bundle `600 root:root`
    - unsigned Dummy-PSBT `600 root:root`
    - signed Dummy-Artefakt `600 root:root`
    - Receipt `600 root:root`
- Rechte:
  - `203` Referenz-/Exportpfade `750 root:root`, Bundle-Dateien `640 root:root`
  - `204` Servicepfade mit `root:btcpayout`, Schreibpfade `770`, Import-/Referenzpfade `750`, Archiv `700 root:root`
- Abschnitts-Endzustand:
  - `203` `stopped`
  - `204` `stopped`
  - Snapshots `post-bitcoin-sim` auf beiden VMs vorhanden

### Dokumentierte Abweichungen und Befunde

- Der erste Lauf auf `204` scheiterte, weil die kleine TCG-VM den Markerpfad innerhalb des urspruenglichen Wait-Fensters nicht erreichte.
- Die anschliessende Journalanalyse auf `204` zeigte einen problematischen `/boot/efi`-Mountpfad, der den Validator in einen schlechten Bootzustand drueckte, bevor der Service sauber anlaufen konnte.
- Das IaC wurde daraufhin reproduzierbar gehaertet:
  - laengeres Wait-Fenster fuer `204`
  - `/etc/fstab` auf `203` und `204` fuer `/boot/efi` mit `nofail,x-systemd.device-timeout=1s`
- Der finale Endlauf zeigte im Journal von `204` zwei erfolgreiche Ausfuehrungen von `ailab-bitcoin-service.service`, jeweils mit sauber geoeffneter und geschlossener `runuser`-Session fuer `btcpayout`.

### Offene Restpunkte

- Die Simulation beweist bewusst keine echte Bitcoin-Core-/HWI-/Electrs-Kompatibilitaet.
- Der Offline-Signer bleibt in diesem Run nur organisatorisch ueber einen root-only Hostpfad simuliert.
- Naechster fachlicher Detailabschnitt ist `Fehleranalyse`.

## Dokumentations-Validator 2026-07-08 Fehleranalyse

### Ziel

- Nachweis, dass der Fehleranalyse-Abschnitt als getrennter Benchmark dokumentiert ist
- Nachweis, dass die Befunde priorisiert und mit realen Artefakten hinterlegt sind
- Nachweis, dass die Querverweise in den laufenden Doku-Dateien konsistent sind
- Nachweis, dass dieser Abschnitt keine neuen Live-Aenderungen auf `ailab2` eingefuehrt hat

### Durchgefuehrte Pruefungen

- Lokal:
  - `rg -n "^### F-00[1-9]|Keine offenen P1|## Analysebasis|## Status" outputs/fehleranalyse-benchmark.md`
  - `rg -n "Fehleranalyse als getrennter Benchmark dokumentiert und validiert|kein offener P1-Befund|abschliessender Self-Audit und Abschlussbericht" outputs/final-summary.md outputs/implementation-log.md outputs/master-plan.md outputs/decision-log.md outputs/risk-register.md`
  - Sichtpruefung von `outputs/fehleranalyse-benchmark.md`
- Remote, read-only:
  - `ls -1` auf allen im Benchmark referenzierten Kernartefakten unter:
    - `/root/ailab2-iac/section-03-config`
    - `/root/ailab2-iac/section-04-network-tor`
    - `/root/ailab2-iac/section-05-backup-monitoring`
    - `/root/ailab2-iac/section-06-bitcoin-simulation`

### Ergebnis

- Erfolgreich.
- `outputs/fehleranalyse-benchmark.md` enthaelt:
  - die Analysebasis
  - das Bewertungsraster
  - neun priorisierte Befunde `F-001` bis `F-009`
  - die Aussage `Keine offenen P1-Befunde im final validierten Endzustand`
- Die Querverweise sind konsistent nachgezogen:
  - `outputs/master-plan.md`
  - `outputs/implementation-log.md`
  - `outputs/final-summary.md`
  - `outputs/decision-log.md` mit `D-035`
  - `outputs/risk-register.md` mit `R-025`
- Alle im Benchmark benannten Kernartefakte auf `ailab2` sind vorhanden.
- Fuer diesen Abschnitt wurden auf `ailab2` keine neuen Live-Aenderungen vorgenommen; die Remote-Pruefungen blieben read-only.

### Dokumentierte Abweichungen und Befunde

- Keine neuen Live-Befunde in diesem Abschnitt; der Benchmark fasst die historischen Nachlaeufe und ihre Ursachen getrennt vom finalen Endzustand zusammen.
- Der finale validierte Endzustand bleibt ohne offenen P1-Befund.

### Offene Restpunkte

- Naechster fachlicher Detailabschnitt ist der abschliessende `Self-Audit` mit Abschlussbericht.
