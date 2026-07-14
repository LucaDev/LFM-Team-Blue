# Final Summary

## Status

- Run gestartet
- Ist-Zustand erhoben und Planungsdokumente angelegt
- Architekturabschnitt dokumentiert und validiert
- Gastgrundlagen / Provisionierung auf `ailab2` umgesetzt und validiert
- Konfigurationsabschnitt auf `ailab2` umgesetzt und validiert
- Netzwerk-/Tor-Abschnitt auf `ailab2` umgesetzt und validiert
- Mini-Hardening fuer Admin-Tor-Zugriff und zentrale Host-Schutzschicht auf `ailab2` umgesetzt und validiert
- Backup-/Monitoring-Abschnitt auf `ailab2` umgesetzt und validiert
- Bitcoin-Konzept auf `ailab2` umgesetzt und validiert
- Fehleranalyse als getrennter Benchmark dokumentiert und validiert
- Noch keine App-Rollouts, keine allgemeinen Service-Onions und keine produktiven Secrets implementiert

## Bisher validiertes Ergebnis

- `101 ct-tor-gateway` blieb im Konfigurationsabschnitt bewusst gestoppt und unveraendert.
- `102`, `103`, `104`, `201`, `202`, `203` und `204` erhielten eine reproduzierbare Minimalbasis mit echten OS-Updates, UTC, Journald-Limits, `/etc/ailab`, Secret-Platzhaltern und zonenspezifischen `/srv`-Pfaden.
- Die VMs erhielten ausschliesslich `qemu-guest-agent` und `cloud-guest-utils` als Zusatzpakete; es wurden keine App-Runtimes wie Docker, Datenbanken oder Webserver ausgerollt.
- Fuer die Bitcoin-Zone blieb alles strikt dummy-only; auf `ailab2` wurden keine Seeds, keine `xprv`, keine `wallet.dat`, keine produktiven Private Keys und keine produktiven API-Schluessel abgelegt.
- Der temporaere Paketversorgungspfad ueber `vmbr90` war waehrend der Umsetzung auf `172.31.90.1:3142` begrenzt; aus allen temporaer angebundenen Gaesten waren `22`, `111`, `8006` und `3128` zum Host blockiert.
- Nach der Validierung des Konfigurationsabschnitts wurden `vmbr90`, `apt-cacher-ng`, `ailab_vmbr90` und alle temporaeren NICs vollstaendig entfernt; zu diesem Zwischenstand endeten alle acht Gaeste wieder im Zustand `stopped`.
- Fuer alle acht Gaeste existieren `post-provision-base` und `post-config-base`.
- Der Host arbeitet jetzt mit einem `nftables`-Deny-by-default-Regelwerk; die operator-only-Pfade sind auf `10.0.2.2 -> tcp/22,8006` und `10.10.10.10 -> tcp/22` verengt.
- `101 ct-tor-gateway` ist als dual-homed Admin-Relay aktiv, stellt einen validierten Admin-Onion fuer Host-SSH bereit und kann nur den explizit freigegebenen SSH-Pfad zum Host auf `10.10.10.1:22` nutzen.
- Der Admin-Onion fuer Host-SSH ist zusaetzlich per v3-Client-Auth auf genau einen root-only Test-Operator-Client verengt; autorisierter Zugriff wurde erfolgreich, unautorisierter Zugriff nach vollem Tor-Bootstrap blockiert validiert.
- `nftables` ist jetzt die einzige wirksame Host-Schutzschicht auf `ailab2`; `pve-firewall` ist `disabled/stopped` und wird nicht mehr parallel wirksam gehalten.
- Fuer `102`, `103`, `104`, `201`, `202`, `203` und `204` ist praktisch nachgewiesen, dass ihre jeweiligen Host-Gateway-Ports `22`, `111`, `8006` und `3128` blockiert sind.
- Fuer alle acht Zielgaeste existiert jetzt zusaetzlich `post-network-tor-base`; der Abschnitt endet mit `101` laufend und allen uebrigen Zielgaesten gestoppt.
- Die Abschnitt-04-Nachlaeufe wegen TCG-/Loop-Timing und eines alten `vmbr90`-Validator-Units sind abgeschlossen; das Endergebnis ist erfolgreich validiert.
- Die operator-only Monitoring-/Backup-Basis ist jetzt aktiv:
  - Host-Exporter auf `10.30.30.1:9100`
  - `101`-Exporter auf `10.10.10.10:9100`
  - `104`-Exporter auf `10.40.40.104:9100`
  - `103` mit `prometheus`, `alertmanager`, `blackbox-exporter`, `node-exporter` und `ntfy` nur auf `10.30.30.103`
- `103` erreicht final genau die vorgesehenen Monitoring-Ziele:
  - `10.30.30.1:9100=open`
  - `10.10.10.10:9100=open`
  - `10.40.40.104:9100=open`
  - `10.30.30.1:{22,111,8006,3128}=blocked`
- Der Host-zu-`104`-Backup-Pfad ist auf `borgrepo` plus `borg serve --restrict-to-path /srv/backup/repos/host` verengt; interaktive Shell-Nutzung auf diesem Pfad wurde praktisch ausgeschlossen.
- Das finale validierte Borg-Archiv ist `ailab2-20260707T212412Z`; der Smoke-Restore extrahiert erfolgreich `host/configs.tgz`, `ct-101/sanitized-configs.tgz` und `ct-101/EXCLUSIONS.txt`.
- `101` wird bewusst nur ueber sanitisierte Rebuild-Artefakte gesichert; `/var/lib/tor/ssh-admin-onion`, Hidden-Service-Keys und service-seitige Client-Auth-Dateien bleiben aus dem Backup ausgeschlossen.
- Fuer die Exporter-Erreichbarkeit in `101` wurde eine gezielte Rueckroute `10.30.30.0/24 via 10.10.10.1 dev eth1` ergaenzt; damit bleibt der Default-Pfad fuer Tor/NAT unveraendert.
- Nach Abschluss von Abschnitt 05 laufen `101`, `103` und `104`; `102`, `201`, `202`, `203` und `204` bleiben gestoppt.
- `203` und `204` bilden jetzt einen strikt dateibasierten Dummy-Bitcoin-Ablauf ab:
  - `203` nur Watch-only-/Referenzrolle
  - `204` nur Hot-Service-Simulation
  - root-only Host-Handoff unter `/root/ailab-runtime/bitcoin-sim-offline`
- Der Dummy-PSBT-Fluss ist Ende-zu-Ende praktisch nachgewiesen:
  - Watch-only-Bundle aus `203`
  - unsigned Dummy-PSBT in `204` Phase 1
  - root-only signed Dummy-Artefakt auf dem Host
  - Dummy-Broadcast-Receipt in `204` Phase 2
- Fuer `203` und `204` ist praktisch nachgewiesen:
  - keine offenen Bitcoin-Listener auf `8332`, `8333`, `18332`, `18333`, `18443`, `18444`, `50001`, `50002`, `50011`, `50012`, `3000`, `3002`
  - `bitcoin_daemons=absent`
  - `wallet_dat=absent`, `seed_files=absent`, `xprv_files=absent`
  - restriktive Rechte fuer Gast- und Host-Handoff-Pfade
- `204` brauchte fuer diese TCG-/EFI-Testbasis eine reproduzierbare Härtung von `/boot/efi` mit `nofail,x-systemd.device-timeout=1s`; danach lief der Validator sauber durch.
- Nach Abschluss von Abschnitt 06 bleiben `203` und `204` wieder `stopped`, und fuer beide existiert `post-bitcoin-sim`.
- Der Fehleranalyse-Benchmark stuetzt sich auf die realen Artefakte aus den Abschnitten 03 bis 06; im final validierten Endzustand blieb kein offener P1-Befund.
- Relevante P2-Befunde waren:
  - kurzzeitige Offenlegung der konkreten Admin-Onion-Adresse in zwei IaC-Validatorartefakten, spaeter redigiert
  - unvollstaendige Borg-/`known_hosts`-Bootstrapbasis vor dem ersten Backup-Lauf
  - `ntfy`-, Bind- und Rueckrouten-Nachlaeufe in der Monitoring-/Backup-Zone
  - ein TCG-/EFI-bedingter Bootblocker auf `204`, der den ersten Bitcoin-Validatorpfad stoerte
- Relevante P3-Befunde waren:
  - `vmbr90`-Validator-False-Negatives und LVM-Retry-Reibung auf `203`
  - Resume-/Loop-Fragilitaet in Abschnitt 04
  - die anfaengliche, unzutreffende Annahme eines wirksamen `torrc.d`-Drop-ins
- Verbleibendes Scope-Risiko: Der lokale Host-SSH-Pfad blieb bewusst mit unveraenderter Host-Authentisierung bestehen; das ist dokumentiert, aber in diesem Run nicht weiter gehaertet.
- Verbleibendes Architektur-Risiko: Das Backupziel liegt weiterhin auf demselben Testhost; eine echte Off-Host-Strategie ist noch nicht umgesetzt.

## Offene Folgeabschnitte

- abschliessender Self-Audit und Abschlussbericht
