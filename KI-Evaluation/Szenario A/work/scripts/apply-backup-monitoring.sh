#!/usr/bin/env bash
set -euo pipefail

SYNC_DIR=/root/homelab-config-sync
STAGING_DIR=/root/homelab-staging
SECRETS_DIR=/root/homelab-secrets
BACKUP_ROOT=/var/lib/homelab-backups

required_files=(
  "$SYNC_DIR/prometheus.yml"
  "$SYNC_DIR/homelab.rules.yml"
  "$SYNC_DIR/blackbox.yml"
  "$SYNC_DIR/homelab-onion-selftest.sh"
  "$SYNC_DIR/homelab-onion-selftest.service"
  "$SYNC_DIR/homelab-onion-selftest.timer"
  "$SYNC_DIR/homelab-backup.sh"
  "$SYNC_DIR/homelab-backup.service"
  "$SYNC_DIR/homelab-backup.timer"
  "$SYNC_DIR/initialize-uptime-kuma.js"
)

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || {
    echo "Missing required sync file: $file" >&2
    exit 1
  }
done

install -d \
  "$STAGING_DIR/ops/config/prometheus/alerts" \
  "$STAGING_DIR/ops/config/blackbox" \
  "$BACKUP_ROOT/runs"

install -m 0644 "$SYNC_DIR/prometheus.yml" "$STAGING_DIR/ops/config/prometheus/prometheus.yml"
install -m 0644 "$SYNC_DIR/homelab.rules.yml" "$STAGING_DIR/ops/config/prometheus/alerts/homelab.rules.yml"
install -m 0644 "$SYNC_DIR/blackbox.yml" "$STAGING_DIR/ops/config/blackbox/blackbox.yml"

pct push 203 "$SYNC_DIR/prometheus.yml" /opt/homelab/ops/config/prometheus/prometheus.yml
pct push 203 "$SYNC_DIR/homelab.rules.yml" /opt/homelab/ops/config/prometheus/alerts/homelab.rules.yml
pct push 203 "$SYNC_DIR/blackbox.yml" /opt/homelab/ops/config/blackbox/blackbox.yml

pct exec 203 -- bash -lc '
set -euo pipefail
cd /opt/homelab/ops
docker compose restart blackbox-exporter prometheus
'

pct push 201 "$SYNC_DIR/homelab-onion-selftest.sh" /usr/local/sbin/homelab-onion-selftest.sh
pct push 201 "$SYNC_DIR/homelab-onion-selftest.service" /etc/systemd/system/homelab-onion-selftest.service
pct push 201 "$SYNC_DIR/homelab-onion-selftest.timer" /etc/systemd/system/homelab-onion-selftest.timer

pct exec 201 -- bash -lc '
set -euo pipefail

install -d -m 0755 /var/lib/prometheus/node-exporter-textfile
touch /etc/default/prometheus-node-exporter

if grep -q "^ARGS=" /etc/default/prometheus-node-exporter; then
  current_args="$(sed -n '\''s/^ARGS="\([^"]*\)".*/\1/p'\'' /etc/default/prometheus-node-exporter | head -n1)"
  if [[ "$current_args" != *"--collector.textfile.directory=/var/lib/prometheus/node-exporter-textfile"* ]]; then
    if [[ -n "$current_args" ]]; then
      new_args="$current_args --collector.textfile.directory=/var/lib/prometheus/node-exporter-textfile"
    else
      new_args="--collector.textfile.directory=/var/lib/prometheus/node-exporter-textfile"
    fi
    sed -i "s|^ARGS=.*|ARGS=\"$new_args\"|" /etc/default/prometheus-node-exporter
  fi
else
  printf '\''ARGS="--collector.textfile.directory=/var/lib/prometheus/node-exporter-textfile"\n'\'' >> /etc/default/prometheus-node-exporter
fi

chmod 700 /usr/local/sbin/homelab-onion-selftest.sh
systemctl daemon-reload
systemctl restart prometheus-node-exporter
systemctl enable --now homelab-onion-selftest.timer
/usr/local/sbin/homelab-onion-selftest.sh
'

install -m 0700 "$SYNC_DIR/homelab-backup.sh" /usr/local/sbin/homelab-backup.sh
install -m 0644 "$SYNC_DIR/homelab-backup.service" /etc/systemd/system/homelab-backup.service
install -m 0644 "$SYNC_DIR/homelab-backup.timer" /etc/systemd/system/homelab-backup.timer
systemctl daemon-reload
systemctl enable --now homelab-backup.timer

UPTIME_KUMA_ENV="$SECRETS_DIR/uptime-kuma.env"
if [[ ! -f "$UPTIME_KUMA_ENV" ]]; then
  {
    echo 'UPTIME_KUMA_ADMIN_USER=homelab-admin'
    printf 'UPTIME_KUMA_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 18)"
  } >"$UPTIME_KUMA_ENV"
  chmod 600 "$UPTIME_KUMA_ENV"
fi

# shellcheck disable=SC1090
source "$UPTIME_KUMA_ENV"

user_count="$(pct exec 203 -- sh -lc "sqlite3 /opt/homelab/ops/data/uptime-kuma/kuma.db 'select count(*) from user;'" | tr -d '\r\n')"
monitor_count="$(pct exec 203 -- sh -lc "sqlite3 /opt/homelab/ops/data/uptime-kuma/kuma.db 'select count(*) from monitor;'" | tr -d '\r\n')"

if [[ "$user_count" == "0" && "$monitor_count" == "0" ]]; then
  pct push 203 "$SYNC_DIR/initialize-uptime-kuma.js" /root/initialize-uptime-kuma.js
  pct exec 203 -- bash -lc "
set -euo pipefail
docker cp /root/initialize-uptime-kuma.js ops-uptime-kuma-1:/tmp/initialize-uptime-kuma.js
docker exec \
  -e UPTIME_KUMA_ADMIN_USER='$UPTIME_KUMA_ADMIN_USER' \
  -e UPTIME_KUMA_ADMIN_PASSWORD='$UPTIME_KUMA_ADMIN_PASSWORD' \
  ops-uptime-kuma-1 \
  node /tmp/initialize-uptime-kuma.js
docker exec ops-uptime-kuma-1 rm -f /tmp/initialize-uptime-kuma.js
docker restart ops-uptime-kuma-1 >/dev/null
rm -f /root/initialize-uptime-kuma.js
"

  if ! grep -q '^Uptime Kuma Login$' "$SECRETS_DIR/service-credentials.txt"; then
    cat >>"$SECRETS_DIR/service-credentials.txt" <<EOF

Uptime Kuma Login
- Username: $UPTIME_KUMA_ADMIN_USER
- Password: $UPTIME_KUMA_ADMIN_PASSWORD
EOF
    chmod 600 "$SECRETS_DIR/service-credentials.txt"
  fi
fi
