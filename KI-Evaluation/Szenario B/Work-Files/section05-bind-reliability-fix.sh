#!/bin/sh
set -eu

SECTION="/root/ailab2-iac/section-05-backup-monitoring"
LOGDIR="$SECTION/logs"
VALIDDIR="$SECTION/validation"

mkdir -p "$LOGDIR" "$VALIDDIR" "$SECTION/staging"

log() {
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOGDIR/section05-bind-reliability-fix.log"
}

write_file() {
  path="$1"
  shift
  tmp="${path}.tmp"
  umask 077
  cat >"$tmp"
  mv "$tmp" "$path"
}

write_file "$SECTION/staging/ailab-wait-ip.sh" <<'EOF'
#!/bin/sh
set -eu
IFACE="${1:?iface}"
ADDR="${2:?addr}"
TRIES="${3:-30}"
i=0
while [ "$i" -lt "$TRIES" ]; do
  if ip -4 addr show dev "$IFACE" | grep -q "inet $ADDR"; then
    exit 0
  fi
  i=$((i + 1))
  sleep 1
done
echo "address $ADDR not present on $IFACE" >&2
exit 1
EOF

log "Installiere Wait-IP-Helper in 101, 103 und 104"
pct push 101 "$SECTION/staging/ailab-wait-ip.sh" /usr/local/sbin/ailab-wait-ip.sh >/dev/null
pct push 103 "$SECTION/staging/ailab-wait-ip.sh" /usr/local/sbin/ailab-wait-ip.sh >/dev/null
pct push 104 "$SECTION/staging/ailab-wait-ip.sh" /usr/local/sbin/ailab-wait-ip.sh >/dev/null
pct exec 101 -- chmod 0755 /usr/local/sbin/ailab-wait-ip.sh
pct exec 103 -- chmod 0755 /usr/local/sbin/ailab-wait-ip.sh
pct exec 104 -- chmod 0755 /usr/local/sbin/ailab-wait-ip.sh

write_file "$SECTION/staging/101-node-exporter-bind-fix.conf" <<'EOF'
[Unit]
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
ExecStartPre=/usr/local/sbin/ailab-wait-ip.sh eth1 10.10.10.10/24 30
Restart=on-failure
RestartSec=5s
EOF
pct exec 101 -- mkdir -p /etc/systemd/system/prometheus-node-exporter.service.d
pct push 101 "$SECTION/staging/101-node-exporter-bind-fix.conf" /etc/systemd/system/prometheus-node-exporter.service.d/20-bind-reliability.conf >/dev/null

write_file "$SECTION/staging/103-bind-fix.conf" <<'EOF'
[Unit]
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
ExecStartPre=/usr/local/sbin/ailab-wait-ip.sh eth0 10.30.30.103/24 30
Restart=on-failure
RestartSec=5s
EOF
pct exec 103 -- mkdir -p /etc/systemd/system/prometheus.service.d
pct exec 103 -- mkdir -p /etc/systemd/system/prometheus-alertmanager.service.d
pct exec 103 -- mkdir -p /etc/systemd/system/prometheus-blackbox-exporter.service.d
pct exec 103 -- mkdir -p /etc/systemd/system/prometheus-node-exporter.service.d
pct exec 103 -- mkdir -p /etc/systemd/system/ntfy.service.d
pct push 103 "$SECTION/staging/103-bind-fix.conf" /etc/systemd/system/prometheus.service.d/20-bind-reliability.conf >/dev/null
pct push 103 "$SECTION/staging/103-bind-fix.conf" /etc/systemd/system/prometheus-alertmanager.service.d/20-bind-reliability.conf >/dev/null
pct push 103 "$SECTION/staging/103-bind-fix.conf" /etc/systemd/system/prometheus-blackbox-exporter.service.d/20-bind-reliability.conf >/dev/null
pct push 103 "$SECTION/staging/103-bind-fix.conf" /etc/systemd/system/prometheus-node-exporter.service.d/20-bind-reliability.conf >/dev/null
pct push 103 "$SECTION/staging/103-bind-fix.conf" /etc/systemd/system/ntfy.service.d/20-bind-reliability.conf >/dev/null

write_file "$SECTION/staging/104-node-exporter-bind-fix.conf" <<'EOF'
[Unit]
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
ExecStartPre=/usr/local/sbin/ailab-wait-ip.sh eth0 10.40.40.104/24 30
Restart=on-failure
RestartSec=5s
EOF
pct exec 104 -- mkdir -p /etc/systemd/system/prometheus-node-exporter.service.d
pct push 104 "$SECTION/staging/104-node-exporter-bind-fix.conf" /etc/systemd/system/prometheus-node-exporter.service.d/20-bind-reliability.conf >/dev/null

log "Lade systemd neu und starte bind-sensitive Dienste sauber neu"
pct exec 101 -- systemctl daemon-reload
pct exec 103 -- systemctl daemon-reload
pct exec 104 -- systemctl daemon-reload
pct exec 101 -- systemctl reset-failed prometheus-node-exporter || true
pct exec 103 -- systemctl reset-failed prometheus prometheus-alertmanager prometheus-blackbox-exporter prometheus-node-exporter ntfy || true
pct exec 104 -- systemctl reset-failed prometheus-node-exporter || true
pct exec 101 -- systemctl restart prometheus-node-exporter
pct exec 103 -- systemctl restart prometheus-alertmanager
pct exec 103 -- systemctl restart prometheus-blackbox-exporter
pct exec 103 -- systemctl restart prometheus-node-exporter
pct exec 103 -- systemctl restart ntfy
pct exec 103 -- systemctl restart prometheus
pct exec 104 -- systemctl restart prometheus-node-exporter

log "Erfasse Bind-Robustheit und aktuelle Listener"
pct exec 101 -- systemctl cat prometheus-node-exporter >"$VALIDDIR/101-node-exporter-unit.txt"
pct exec 103 -- systemctl cat prometheus >"$VALIDDIR/103-prometheus-unit.txt"
pct exec 103 -- systemctl cat prometheus-alertmanager >"$VALIDDIR/103-alertmanager-unit.txt"
pct exec 103 -- systemctl cat prometheus-blackbox-exporter >"$VALIDDIR/103-blackbox-unit.txt"
pct exec 103 -- systemctl cat ntfy >"$VALIDDIR/103-ntfy-unit.txt"
pct exec 104 -- systemctl cat prometheus-node-exporter >"$VALIDDIR/104-node-exporter-unit.txt"
pct exec 101 -- systemctl is-active prometheus-node-exporter >"$VALIDDIR/101-node-exporter-active.txt"
pct exec 103 -- systemctl is-active prometheus prometheus-alertmanager prometheus-blackbox-exporter prometheus-node-exporter ntfy >"$VALIDDIR/103-systemctl-active.txt"
pct exec 104 -- systemctl is-active prometheus-node-exporter >"$VALIDDIR/104-node-exporter-active.txt"
pct exec 101 -- ss -ltnp >"$VALIDDIR/101-listeners.txt"
pct exec 103 -- ss -ltnp >"$VALIDDIR/103-listeners.txt"
pct exec 104 -- ss -ltnp >"$VALIDDIR/104-listeners.txt"

log "Bind-Robustheit aktualisiert"
