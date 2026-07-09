#!/bin/sh
set -eu

SECTION="/root/ailab2-iac/section-05-backup-monitoring"
LOGDIR="$SECTION/logs"
VALIDDIR="$SECTION/validation"
MANIFESTDIR="$SECTION/manifests"
PORTDIR="$SECTION/port-checks"
STAGINGROOT="/var/lib/ailab-backup"
CURRENT="$STAGINGROOT/staging/current"
RUNTIME_ROOT="/root/ailab-runtime"
BORG_RUNTIME="$RUNTIME_ROOT/borg-host-to-104"
TEXTFILE_DIR="/var/lib/prometheus/node-exporter"
VMBR90_ADDR="172.31.90.1"

mkdir -p "$LOGDIR" "$VALIDDIR" "$MANIFESTDIR" "$PORTDIR" "$SECTION/scripts" "$SECTION/staging" \
  "$STAGINGROOT/staging" "$CURRENT" "$TEXTFILE_DIR" "$RUNTIME_ROOT" "$BORG_RUNTIME"

log() {
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOGDIR/section05-apply.log"
}

write_file() {
  path="$1"
  shift
  tmp="${path}.tmp"
  umask 077
  cat >"$tmp"
  mv "$tmp" "$path"
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

collect_ct_file() {
  vmid="$1"
  src="$2"
  dst="$3"
  mkdir -p "$(dirname "$dst")"
  pct exec "$vmid" -- cat "$src" >"$dst"
}

collect_ct_tar() {
  vmid="$1"
  dst="$2"
  shift 2
  mkdir -p "$(dirname "$dst")"
  pct exec "$vmid" -- tar -C / -czf - "$@" >"$dst"
}

write_file "/etc/sysctl.d/60-ailab-zone-routing.conf" <<'EOF'
net.ipv4.ip_forward = 1
EOF
sysctl -q -p /etc/sysctl.d/60-ailab-zone-routing.conf

write_file "/etc/nftables.conf" <<'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet ailab {
  set operator_v4 {
    type ipv4_addr
    elements = { 10.0.2.2 }
  }

  chain input {
    type filter hook input priority filter; policy drop;

    iifname "lo" accept
    ct state established,related accept
    ct state invalid drop

    iifname "vmbr0" ip saddr @operator_v4 tcp dport { 22, 8006 } accept
    iifname "vmbr10" ip saddr 10.10.10.10 tcp dport 22 accept
    iifname "vmbr30" ip saddr 10.30.30.103 ip daddr 10.30.30.1 tcp dport 9100 accept comment "ct-monitoring -> host-node-exporter"

    reject with icmpx type admin-prohibited
  }

  chain forward {
    type filter hook forward priority filter; policy drop;

    ct state established,related accept

    iifname "vmbr30" oifname "vmbr10" ip saddr 10.30.30.103 ip daddr 10.10.10.10 tcp dport 9100 accept comment "ct-monitoring -> ct-tor-gateway node-exporter"
    iifname "vmbr30" oifname "vmbr40" ip saddr 10.30.30.103 ip daddr 10.40.40.104 tcp dport 9100 accept comment "ct-monitoring -> ct-backup node-exporter"

    reject with icmpx type admin-prohibited
  }

  chain output {
    type filter hook output priority filter; policy accept;
  }
}
EOF
nft -f /etc/nftables.conf
systemctl enable --now nftables >/dev/null
systemctl disable --now pve-firewall >/dev/null 2>&1 || true

log "Installiere node_exporter in 101 und erfasse Paketmanifeste"
pct exec 101 -- sh -lc 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends prometheus-node-exporter' \
  >"$LOGDIR/101-node-exporter-install.log" 2>&1

dpkg-query -W -f='${Package} ${Version}\n' | sort >"$MANIFESTDIR/host-section05-package-manifest.txt"
pct exec 101 -- dpkg-query -W -f='${Package} ${Version}\n' | sort >"$MANIFESTDIR/101-ct-tor-gateway-section05-packages.txt"
pct exec 103 -- dpkg-query -W -f='${Package} ${Version}\n' | sort >"$MANIFESTDIR/103-ct-monitoring-section05-packages.txt"
pct exec 104 -- dpkg-query -W -f='${Package} ${Version}\n' | sort >"$MANIFESTDIR/104-ct-backup-section05-packages.txt"

log "Schreibe Host- und Gastkonfigurationen"
write_file "/etc/default/prometheus-node-exporter" <<'EOF'
ARGS="--web.listen-address=10.30.30.1:9100 --collector.textfile.directory=/var/lib/prometheus/node-exporter"
EOF

write_file "/usr/local/sbin/ailab-ssh-auth-metrics.sh" <<'EOF'
#!/bin/sh
set -eu
OUTDIR="/var/lib/prometheus/node-exporter"
TMP="$(mktemp "$OUTDIR/.ssh-auth.XXXXXX")"
FAILED="$(journalctl -u ssh --since '1 hour ago' --no-pager 2>/dev/null | grep -Eic 'Failed password|Invalid user|authentication failure|max auth attempts|Disconnected from authenticating user' || true)"
INVALID="$(journalctl -u ssh --since '1 hour ago' --no-pager 2>/dev/null | grep -Eic 'Invalid user' || true)"
cat >"$TMP" <<METRICS
# HELP ailab_ssh_failed_auth_1h Failed SSH authentication events seen on the host during the last hour.
# TYPE ailab_ssh_failed_auth_1h gauge
ailab_ssh_failed_auth_1h $FAILED
# HELP ailab_ssh_invalid_user_1h Invalid SSH user events seen on the host during the last hour.
# TYPE ailab_ssh_invalid_user_1h gauge
ailab_ssh_invalid_user_1h $INVALID
METRICS
chmod 0644 "$TMP"
mv "$TMP" "$OUTDIR/ssh-auth.prom"
EOF
chmod 0755 "/usr/local/sbin/ailab-ssh-auth-metrics.sh"

write_file "/etc/systemd/system/ailab-ssh-auth-metrics.service" <<'EOF'
[Unit]
Description=Refresh AILAB host SSH auth metrics for node_exporter

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ailab-ssh-auth-metrics.sh
EOF

write_file "/etc/systemd/system/ailab-ssh-auth-metrics.timer" <<'EOF'
[Unit]
Description=Run AILAB host SSH auth metric refresh every five minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

umask 077
if [ ! -f "$BORG_RUNTIME/passphrase" ]; then
  openssl rand -hex 32 >"$BORG_RUNTIME/passphrase"
fi
if [ ! -f "$BORG_RUNTIME/id_ed25519" ]; then
  ssh-keygen -q -t ed25519 -N '' -f "$BORG_RUNTIME/id_ed25519"
fi

pct exec 104 -- sh -lc '
set -eu
id -u borgrepo >/dev/null 2>&1 || useradd --system --home-dir /var/lib/borgrepo --create-home --shell /bin/sh borgrepo
install -d -o borgrepo -g borgrepo -m 0700 /var/lib/borgrepo/.ssh
install -d -o borgrepo -g borgrepo -m 0700 /srv/backup/repos
install -d -o borgrepo -g borgrepo -m 0700 /srv/backup/repos/host
'

write_file "$SECTION/staging/104-borgrepo-authorized_keys" <<EOF
restrict,command="/usr/bin/borg serve --restrict-to-path /srv/backup/repos/host" $(cat "$BORG_RUNTIME/id_ed25519.pub")
EOF
pct push 104 "$SECTION/staging/104-borgrepo-authorized_keys" /var/lib/borgrepo/.ssh/authorized_keys >/dev/null
pct exec 104 -- chown borgrepo:borgrepo /var/lib/borgrepo/.ssh/authorized_keys
pct exec 104 -- chmod 0600 /var/lib/borgrepo/.ssh/authorized_keys

write_file "$SECTION/staging/104-sshd-borgrepo.conf" <<'EOF'
Match User borgrepo
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PubkeyAuthentication yes
    PermitTTY no
    X11Forwarding no
    AllowAgentForwarding no
    AllowTcpForwarding no
    AllowStreamLocalForwarding no
    GatewayPorts no
    PermitTunnel no
    PermitUserRC no
    ForceCommand /usr/bin/borg serve --restrict-to-path /srv/backup/repos/host
EOF
pct push 104 "$SECTION/staging/104-sshd-borgrepo.conf" /etc/ssh/sshd_config.d/10-ailab-borgrepo.conf >/dev/null
pct exec 104 -- chmod 0644 /etc/ssh/sshd_config.d/10-ailab-borgrepo.conf

write_file "$SECTION/staging/101-prometheus-node-exporter.default" <<'EOF'
ARGS="--web.listen-address=10.10.10.10:9100"
EOF
pct push 101 "$SECTION/staging/101-prometheus-node-exporter.default" /etc/default/prometheus-node-exporter >/dev/null

write_file "$SECTION/staging/103-prometheus.default" <<'EOF'
ARGS="--config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --web.console.templates=/usr/share/prometheus/consoles --web.console.libraries=/usr/share/prometheus/console_libraries --web.listen-address=10.30.30.103:9090"
EOF
pct push 103 "$SECTION/staging/103-prometheus.default" /etc/default/prometheus >/dev/null

write_file "$SECTION/staging/103-prometheus-alertmanager.default" <<'EOF'
ARGS="--config.file=/etc/prometheus/alertmanager.yml --storage.path=/var/lib/prometheus/alertmanager --web.listen-address=10.30.30.103:9093 --cluster.listen-address=10.30.30.103:9094"
EOF
pct push 103 "$SECTION/staging/103-prometheus-alertmanager.default" /etc/default/prometheus-alertmanager >/dev/null

write_file "$SECTION/staging/103-prometheus-blackbox-exporter.default" <<'EOF'
ARGS="--config.file /etc/prometheus/blackbox.yml --web.listen-address=10.30.30.103:9115"
EOF
pct push 103 "$SECTION/staging/103-prometheus-blackbox-exporter.default" /etc/default/prometheus-blackbox-exporter >/dev/null

write_file "$SECTION/staging/103-prometheus-node-exporter.default" <<'EOF'
ARGS="--web.listen-address=10.30.30.103:9100"
EOF
pct push 103 "$SECTION/staging/103-prometheus-node-exporter.default" /etc/default/prometheus-node-exporter >/dev/null

write_file "$SECTION/staging/103-prometheus.yml" <<'EOF'
global:
  scrape_interval: 30s
  evaluation_interval: 30s
  external_labels:
    site: "ailab2"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - "10.30.30.103:9093"

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - "10.30.30.103:9090"

  - job_name: monitoring-node
    static_configs:
      - targets:
          - "10.30.30.103:9100"

  - job_name: host-node
    static_configs:
      - targets:
          - "10.30.30.1:9100"

  - job_name: tor-gateway-node
    static_configs:
      - targets:
          - "10.10.10.10:9100"

  - job_name: backup-node
    static_configs:
      - targets:
          - "10.40.40.104:9100"

  - job_name: blackbox-http
    metrics_path: /probe
    params:
      module:
        - http_2xx
    static_configs:
      - targets:
          - "http://10.30.30.103:2586/"
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: 10.30.30.103:9115
EOF
pct push 103 "$SECTION/staging/103-prometheus.yml" /etc/prometheus/prometheus.yml >/dev/null

pct exec 103 -- mkdir -p /etc/prometheus/rules
write_file "$SECTION/staging/103-ailab-rules.yml" <<'EOF'
groups:
  - name: ailab-baseline
    rules:
      - alert: AilabTargetDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Prometheus target down"
          description: "{{ $labels.job }} on {{ $labels.instance }} is unreachable."

      - alert: AilabBackupStale
        expr: time() - ailab_backup_last_success_timestamp_seconds > 93600
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Backup stale"
          description: "The host backup has not completed successfully within the last 26 hours."

      - alert: AilabHostSshFailuresRecent
        expr: ailab_ssh_failed_auth_1h > 0
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Recent host SSH failures"
          description: "The host observed {{ $value }} failed SSH authentication events during the last hour."

      - alert: AilabNtfyUnavailable
        expr: probe_success{job="blackbox-http"} == 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "ntfy endpoint unavailable"
          description: "The operator-only ntfy endpoint on ct-monitoring is not returning HTTP 2xx."
EOF
pct push 103 "$SECTION/staging/103-ailab-rules.yml" /etc/prometheus/rules/ailab.rules.yml >/dev/null

write_file "$SECTION/staging/103-alertmanager.yml" <<'EOF'
global:
  resolve_timeout: 5m

route:
  receiver: ntfy-operator
  group_by: ["alertname", "job", "instance"]
  group_wait: 15s
  group_interval: 5m
  repeat_interval: 4h

receivers:
  - name: ntfy-operator
    webhook_configs:
      - url: "http://10.30.30.103:2586/ailab-monitoring-alerts"
        send_resolved: true
EOF
pct push 103 "$SECTION/staging/103-alertmanager.yml" /etc/prometheus/alertmanager.yml >/dev/null

write_file "$SECTION/staging/103-ntfy-server.yml" <<'EOF'
base-url: "http://10.30.30.103:2586"
listen-http: "10.30.30.103:2586"
cache-file: "/var/cache/ntfy/cache.db"
cache-duration: "24h"
behind-proxy: false
enable-signup: false
enable-login: false
enable-reservations: false
web-root: /
EOF
pct push 103 "$SECTION/staging/103-ntfy-server.yml" /etc/ntfy/server.yml >/dev/null

write_file "$SECTION/staging/103-prometheus-lxc.override" <<'EOF'
[Service]
PrivateUsers=false
EOF
pct exec 103 -- mkdir -p /etc/systemd/system/prometheus.service.d
pct push 103 "$SECTION/staging/103-prometheus-lxc.override" /etc/systemd/system/prometheus.service.d/10-lxc.conf >/dev/null

write_file "$SECTION/staging/104-prometheus-node-exporter.default" <<'EOF'
ARGS="--web.listen-address=10.40.40.104:9100"
EOF
pct push 104 "$SECTION/staging/104-prometheus-node-exporter.default" /etc/default/prometheus-node-exporter >/dev/null

pct exec 104 -- sshd -t
pct exec 103 -- promtool check config /etc/prometheus/prometheus.yml >"$VALIDDIR/103-promtool-check.txt"
pct exec 103 -- promtool check rules /etc/prometheus/rules/ailab.rules.yml >"$VALIDDIR/103-promtool-rules-check.txt"
pct exec 103 -- amtool check-config /etc/prometheus/alertmanager.yml >"$VALIDDIR/103-amtool-check.txt"

log "Aktiviere und starte Dienste"
systemctl daemon-reload
systemctl restart prometheus-node-exporter
systemctl enable --now ailab-ssh-auth-metrics.timer >/dev/null
systemctl start ailab-ssh-auth-metrics.service

pct exec 101 -- systemctl restart prometheus-node-exporter
pct exec 101 -- systemctl enable prometheus-node-exporter >/dev/null

pct exec 103 -- systemctl daemon-reload
pct exec 103 -- systemctl restart prometheus-node-exporter
pct exec 103 -- systemctl restart prometheus-blackbox-exporter
pct exec 103 -- systemctl restart prometheus-alertmanager
pct exec 103 -- systemctl restart ntfy
pct exec 103 -- systemctl restart prometheus
pct exec 103 -- systemctl enable prometheus prometheus-alertmanager prometheus-blackbox-exporter prometheus-node-exporter ntfy >/dev/null

pct exec 104 -- systemctl daemon-reload
pct exec 104 -- systemctl restart ssh
pct exec 104 -- systemctl restart prometheus-node-exporter
pct exec 104 -- systemctl enable ssh prometheus-node-exporter >/dev/null

log "Initialisiere Borg-Repository und Backup-Lauf"
write_file "/usr/local/sbin/ailab-run-backup.sh" <<'EOF'
#!/bin/sh
set -eu

RUNTIME="/root/ailab-runtime/borg-host-to-104"
TEXTFILE_DIR="/var/lib/prometheus/node-exporter"
WORKROOT="/var/lib/ailab-backup"
CURRENT="$WORKROOT/staging/current"
TMPROOT="$WORKROOT/staging"
SECTION="/root/ailab2-iac/section-05-backup-monitoring"
TMPDIR="$(mktemp -d "$TMPROOT/.backup.XXXXXX")"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ARCHIVE="ailab2-$STAMP"
export BORG_RSH="ssh -i $RUNTIME/id_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$RUNTIME/known_hosts"
export BORG_PASSCOMMAND="/usr/bin/cat $RUNTIME/passphrase"
export BORG_REPO="ssh://borgrepo@10.40.40.104/srv/backup/repos/host"

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

mkdir -p "$TMPDIR/host" "$TMPDIR/pct-config" "$TMPDIR/ct-101" "$TMPDIR/ct-103" "$TMPDIR/ct-104" "$CURRENT" "$TEXTFILE_DIR"

tar -C / -czf "$TMPDIR/host/configs.tgz" \
  etc/nftables.conf \
  etc/network/interfaces \
  etc/apt/sources.list.d \
  etc/sysctl.d \
  etc/systemd/system \
  etc/default/prometheus-node-exporter \
  etc/ssh/sshd_config \
  etc/ssh/ssh_config \
  usr/local/sbin/ailab-run-backup.sh \
  usr/local/sbin/ailab-ssh-auth-metrics.sh \
  root/ailab2-iac

pct config 101 > "$TMPDIR/pct-config/101.conf"
pct config 103 > "$TMPDIR/pct-config/103.conf"
pct config 104 > "$TMPDIR/pct-config/104.conf"

pct exec 101 -- tar -C / -czf - \
  etc/tor/torrc \
  etc/network/interfaces \
  etc/default/prometheus-node-exporter \
  etc/systemd/system > "$TMPDIR/ct-101/sanitized-configs.tgz"
pct exec 103 -- tar -C / -czf - \
  etc/prometheus \
  etc/default/prometheus \
  etc/default/prometheus-alertmanager \
  etc/default/prometheus-blackbox-exporter \
  etc/default/prometheus-node-exporter \
  etc/ntfy \
  etc/systemd/system > "$TMPDIR/ct-103/configs.tgz"
pct exec 104 -- tar -C / -czf - \
  etc/ssh \
  etc/default/prometheus-node-exporter \
  etc/systemd/system > "$TMPDIR/ct-104/configs.tgz"

pct exec 101 -- dpkg-query -W -f='${Package} ${Version}\n' | sort > "$TMPDIR/ct-101/package-manifest.txt"
pct exec 103 -- dpkg-query -W -f='${Package} ${Version}\n' | sort > "$TMPDIR/ct-103/package-manifest.txt"
pct exec 104 -- dpkg-query -W -f='${Package} ${Version}\n' | sort > "$TMPDIR/ct-104/package-manifest.txt"
dpkg-query -W -f='${Package} ${Version}\n' | sort > "$TMPDIR/host/package-manifest.txt"

cat > "$TMPDIR/ct-101/EXCLUSIONS.txt" <<EXC
Automated backup intentionally excludes:
- /var/lib/tor/ssh-admin-onion/
- any Tor hidden service private key material
- service-side client-authorization files under /var/lib/tor/ssh-admin-onion/authorized_clients/
Restore expectation:
- rebuild 101 from sanitized configuration and generate a new onion identity plus new client auth
EXC

(cd "$TMPDIR" && find . -type f | sort | xargs sha256sum) > "$TMPDIR/SHA256SUMS"

rm -rf "$CURRENT"
mkdir -p "$CURRENT"
cp -a "$TMPDIR"/. "$CURRENT"/

if ! borg info >/dev/null 2>&1; then
  borg init --encryption=repokey-blake2
fi

cd "$CURRENT"
borg create --stats "::${ARCHIVE}" host pct-config ct-101 ct-103 ct-104 SHA256SUMS > "$SECTION/validation/borg-create.txt" 2>&1
borg prune --list --keep-daily=7 --keep-weekly=4 --keep-monthly=3 > "$SECTION/validation/borg-prune.txt" 2>&1
printf '%s\n' "$ARCHIVE" > "$SECTION/validation/latest-borg-archive.txt"

NOW="$(date +%s)"
TMPMETRIC="$(mktemp "$TEXTFILE_DIR/.backup.XXXXXX")"
cat >"$TMPMETRIC" <<METRICS
# HELP ailab_backup_last_success_timestamp_seconds Unix timestamp of the last successful host backup run.
# TYPE ailab_backup_last_success_timestamp_seconds gauge
ailab_backup_last_success_timestamp_seconds $NOW
METRICS
chmod 0644 "$TMPMETRIC"
mv "$TMPMETRIC" "$TEXTFILE_DIR/backup.prom"
EOF
chmod 0755 /usr/local/sbin/ailab-run-backup.sh

write_file "/etc/systemd/system/ailab-backup.service" <<'EOF'
[Unit]
Description=Run AILAB host Borg backup to ct-backup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ailab-run-backup.sh
EOF

write_file "/etc/systemd/system/ailab-backup.timer" <<'EOF'
[Unit]
Description=Run AILAB host Borg backup daily

[Timer]
OnCalendar=*-*-* 04:25:00 UTC
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now ailab-backup.timer >/dev/null
systemctl start ailab-backup.service

log "Erfasse temporaeren vmbr90-Nachweis und baue Hilfsnetz vollstaendig zurueck"
port_check_vmbr90 103 "$PORTDIR/103-vmbr90-final.txt"
port_check_vmbr90 104 "$PORTDIR/104-vmbr90-final.txt"

pct exec 103 -- rm -f /etc/apt/apt.conf.d/90ailab-proxy
pct exec 104 -- rm -f /etc/apt/apt.conf.d/90ailab-proxy

pct shutdown 103 --timeout 60 || true
pct shutdown 104 --timeout 60 || true
sleep 5
pct set 103 -delete net9 >/dev/null
pct set 104 -delete net9 >/dev/null
if ip link show vmbr90 >/dev/null 2>&1; then
  ip link set vmbr90 down || true
  ip link delete vmbr90 type bridge || true
fi
rm -f /etc/apt-cacher-ng/acng.conf.d/90-ailab-vmbr90.conf
apt-get purge -y apt-cacher-ng >"$LOGDIR/apt-cacher-ng-purge.log" 2>&1 || true

pct start 103
pct start 104
sleep 10

log "Sammle Basisvalidierung"
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
stat -c '%n %a %U:%G' "$BORG_RUNTIME" "$BORG_RUNTIME/id_ed25519" "$BORG_RUNTIME/id_ed25519.pub" "$BORG_RUNTIME/known_hosts" "$BORG_RUNTIME/passphrase" >"$VALIDDIR/host-borg-runtime-perms.txt"
pct exec 104 -- cat /etc/ssh/ssh_host_ed25519_key.pub >"$SECTION/staging/104-ssh-host-ed25519.pub"
ssh-keygen -l -f "$SECTION/staging/104-ssh-host-ed25519.pub" >"$VALIDDIR/104-ssh-hostkey-fingerprint.txt"
rm -f "$SECTION/staging/104-ssh-host-ed25519.pub"

log "Abschnitt 05 Apply abgeschlossen"
