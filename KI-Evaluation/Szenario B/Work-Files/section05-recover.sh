#!/bin/sh
set -eu

SECTION="/root/ailab2-iac/section-05-backup-monitoring"
LOGDIR="$SECTION/logs"
VALIDDIR="$SECTION/validation"
PORTDIR="$SECTION/port-checks"
BORG_RUNTIME="/root/ailab-runtime/borg-host-to-104"
VMBR90_ADDR="172.31.90.1"

mkdir -p "$LOGDIR" "$VALIDDIR" "$PORTDIR"

log() {
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOGDIR/section05-recover.log"
}

port_check_vmbr90() {
  vmid="$1"
  outfile="$2"
  pct exec "$vmid" -- sh -lc '
python3 - <<'"'"'PY'"'"'
import socket
targets = [3142, 22, 111, 8006, 3128]
host = "'"$VMBR90_ADDR"'"
for port in targets:
    s = socket.socket()
    s.settimeout(2.0)
    try:
        s.connect((host, port))
    except Exception:
        state = "blocked"
    else:
        state = "open"
    finally:
        s.close()
    print(f"tcp/{port}={state}")
PY' >"$outfile"
}

log "Korrigiere Borg-runtime und known_hosts"
install -d -m 0700 "$BORG_RUNTIME"
pct exec 104 -- cat /etc/ssh/ssh_host_ed25519_key.pub >"$SECTION/staging/104-ssh-host-ed25519.pub"
KEYLINE="$(cat "$SECTION/staging/104-ssh-host-ed25519.pub")"
umask 077
cat >"$BORG_RUNTIME/known_hosts" <<EOF
10.40.40.104 $KEYLINE
[10.40.40.104]:22 $KEYLINE
EOF
chmod 0600 "$BORG_RUNTIME/known_hosts"
chmod 0600 "$BORG_RUNTIME/id_ed25519" "$BORG_RUNTIME/id_ed25519.pub" "$BORG_RUNTIME/passphrase"
rm -f "$SECTION/staging/104-ssh-host-ed25519.pub"

log "Bringe ntfy mit den benoetigten Paketpfaden hoch"
pct exec 103 -- sh -lc '
set -eu
install -d -o _ntfy -g _ntfy -m 0750 /var/cache/ntfy
install -d -o _ntfy -g _ntfy -m 0750 /var/lib/ntfy
systemctl reset-failed ntfy || true
systemctl restart ntfy
'

log "Starte Backup-Dienst erneut"
systemctl reset-failed ailab-backup.service || true
systemctl start ailab-backup.service

log "Erfasse temporaeren vmbr90-Nachweis und baue Hilfsnetz vollstaendig zurueck"
port_check_vmbr90 103 "$PORTDIR/103-vmbr90-final.txt"
port_check_vmbr90 104 "$PORTDIR/104-vmbr90-final.txt"

pct exec 103 -- rm -f /etc/apt/apt.conf.d/90ailab-proxy
pct exec 104 -- rm -f /etc/apt/apt.conf.d/90ailab-proxy

pct shutdown 103 --timeout 60 || true
pct shutdown 104 --timeout 60 || true
sleep 5
pct set 103 -delete net9 >/dev/null 2>&1 || true
pct set 104 -delete net9 >/dev/null 2>&1 || true
if ip link show vmbr90 >/dev/null 2>&1; then
  ip link set vmbr90 down || true
  ip link delete vmbr90 type bridge || true
fi
rm -f /etc/apt-cacher-ng/acng.conf.d/90-ailab-vmbr90.conf
apt-get purge -y apt-cacher-ng >"$LOGDIR/apt-cacher-ng-purge.log" 2>&1 || true

pct start 103 >/dev/null
pct start 104 >/dev/null
sleep 10

log "Ergaenze Basisvalidierung"
systemctl is-enabled nftables pve-firewall prometheus-node-exporter ailab-backup.timer ailab-ssh-auth-metrics.timer >"$VALIDDIR/host-systemctl-enabled.txt" 2>&1 || true
systemctl is-active nftables pve-firewall prometheus-node-exporter ailab-backup.timer ailab-ssh-auth-metrics.timer >"$VALIDDIR/host-systemctl-active.txt" 2>&1 || true
ss -ltnp >"$VALIDDIR/host-listeners.txt"
nft list ruleset >"$VALIDDIR/host-nft-ruleset.txt"
sysctl net.ipv4.ip_forward >"$VALIDDIR/host-ip-forward.txt"
ip link show vmbr90 >"$VALIDDIR/vmbr90-link-state.txt" 2>&1 || true

pct exec 101 -- ss -ltnp >"$VALIDDIR/101-listeners.txt"
pct exec 103 -- ss -ltnp >"$VALIDDIR/103-listeners.txt"
pct exec 104 -- ss -ltnp >"$VALIDDIR/104-listeners.txt"
pct exec 101 -- systemctl is-enabled prometheus-node-exporter >"$VALIDDIR/101-node-exporter-enabled.txt" 2>&1 || true
pct exec 101 -- systemctl is-active prometheus-node-exporter >"$VALIDDIR/101-node-exporter-active.txt" 2>&1 || true
pct exec 103 -- systemctl is-enabled prometheus prometheus-alertmanager prometheus-blackbox-exporter prometheus-node-exporter ntfy >"$VALIDDIR/103-systemctl-enabled.txt" 2>&1 || true
pct exec 103 -- systemctl is-active prometheus prometheus-alertmanager prometheus-blackbox-exporter prometheus-node-exporter ntfy >"$VALIDDIR/103-systemctl-active.txt" 2>&1 || true
pct exec 104 -- systemctl is-enabled ssh prometheus-node-exporter >"$VALIDDIR/104-systemctl-enabled.txt" 2>&1 || true
pct exec 104 -- systemctl is-active ssh prometheus-node-exporter >"$VALIDDIR/104-systemctl-active.txt" 2>&1 || true
pct exec 104 -- sshd -T -C user=borgrepo,addr=10.40.40.1,host=ct-backup >"$VALIDDIR/104-borgrepo-sshd-effective.txt"
pct exec 104 -- stat -c '%n %a %U:%G' /var/lib/borgrepo /var/lib/borgrepo/.ssh /var/lib/borgrepo/.ssh/authorized_keys /srv/backup /srv/backup/repos /srv/backup/repos/host >"$VALIDDIR/104-borgrepo-paths.txt"
stat -c '%n %a %U:%G' /root/ailab-runtime /root/ailab-runtime/borg-host-to-104 /root/ailab-runtime/borg-host-to-104/id_ed25519 /root/ailab-runtime/borg-host-to-104/id_ed25519.pub /root/ailab-runtime/borg-host-to-104/known_hosts /root/ailab-runtime/borg-host-to-104/passphrase >"$VALIDDIR/host-borg-runtime-perms.txt"
pct exec 104 -- cat /etc/ssh/ssh_host_ed25519_key.pub >"$SECTION/staging/104-ssh-host-ed25519.pub"
ssh-keygen -l -f "$SECTION/staging/104-ssh-host-ed25519.pub" >"$VALIDDIR/104-ssh-hostkey-fingerprint.txt"
rm -f "$SECTION/staging/104-ssh-host-ed25519.pub"

log "Section 05 Recovery abgeschlossen"
