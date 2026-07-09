#!/usr/bin/env bash
set -euo pipefail

SYNC_DIR=/root/homelab-config-sync
SECRETS_DIR=/root/homelab-secrets
STAGING_DIR=/root/homelab-staging

required_files=(
  "$SYNC_DIR/host-nftables.conf"
  "$SYNC_DIR/ops-docker-compose.yml"
  "$SYNC_DIR/alertmanager.yml"
  "$SYNC_DIR/alert_forwarder.py"
  "$SYNC_DIR/homelab.rules.yml"
  "$SYNC_DIR/tor-edge-Caddyfile"
  "$SYNC_DIR/homelab-onion-selftest.sh"
  "$SYNC_DIR/homelab-backup.sh"
  "$SYNC_DIR/app-core-docker-compose.yml"
)

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || {
    echo "Missing required sync file: $file" >&2
    exit 1
  }
done

upsert_env_file() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

backup_dir="/root/homelab-backups/findings-remediation-$(date +%Y%m%d-%H%M%S)"
install -d "$backup_dir"
cp -a /etc/nftables.conf "$backup_dir/nftables.conf.before"

install -m 0644 "$SYNC_DIR/host-nftables.conf" /etc/nftables.conf
nft -c -f /etc/nftables.conf
systemctl enable --now nftables >/dev/null
systemctl reload nftables

systemctl disable --now rpcbind.service rpcbind.socket >/dev/null 2>&1 || true

if [[ -f "$SECRETS_DIR/alerts-topic.env" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_DIR/alerts-topic.env"
fi

if [[ -z "${HOMELAB_ALERT_TOPIC:-}" ]]; then
  HOMELAB_ALERT_TOPIC="homelab-alerts-$(openssl rand -hex 12)"
  cat >"$SECRETS_DIR/alerts-topic.env" <<EOF
HOMELAB_ALERT_TOPIC=${HOMELAB_ALERT_TOPIC}
EOF
  chmod 600 "$SECRETS_DIR/alerts-topic.env"
fi

upsert_env_file "$SECRETS_DIR/ops.env" HOMELAB_ALERT_TOPIC "$HOMELAB_ALERT_TOPIC"

install -d \
  "$STAGING_DIR/ops/config/alertmanager" \
  "$STAGING_DIR/ops/config/alert-forwarder" \
  "$STAGING_DIR/ops/config/prometheus/alerts" \
  "$STAGING_DIR/tor-edge" \
  "$STAGING_DIR/app-core"

install -m 0644 "$SYNC_DIR/ops-docker-compose.yml" "$STAGING_DIR/ops/docker-compose.yml"
install -m 0644 "$SYNC_DIR/alertmanager.yml" "$STAGING_DIR/ops/config/alertmanager/alertmanager.yml"
install -m 0644 "$SYNC_DIR/alert_forwarder.py" "$STAGING_DIR/ops/config/alert-forwarder/alert_forwarder.py"
install -m 0644 "$SYNC_DIR/homelab.rules.yml" "$STAGING_DIR/ops/config/prometheus/alerts/homelab.rules.yml"
install -m 0644 "$SYNC_DIR/tor-edge-Caddyfile" "$STAGING_DIR/tor-edge/Caddyfile"
install -m 0644 "$SYNC_DIR/app-core-docker-compose.yml" "$STAGING_DIR/app-core/docker-compose.yml"

pct exec 203 -- bash -lc '
set -euo pipefail
mkdir -p /opt/homelab/ops/config/alert-forwarder /opt/homelab/ops/data/ntfy/cache
'
pct push 203 "$SYNC_DIR/ops-docker-compose.yml" /opt/homelab/ops/docker-compose.yml
pct push 203 "$SYNC_DIR/alertmanager.yml" /opt/homelab/ops/config/alertmanager/alertmanager.yml
pct push 203 "$SYNC_DIR/alert_forwarder.py" /opt/homelab/ops/config/alert-forwarder/alert_forwarder.py
pct push 203 "$SYNC_DIR/homelab.rules.yml" /opt/homelab/ops/config/prometheus/alerts/homelab.rules.yml
pct exec 203 -- bash -lc "
set -euo pipefail
cd /opt/homelab/ops
if grep -q '^HOMELAB_ALERT_TOPIC=' .env 2>/dev/null; then
  sed -i 's|^HOMELAB_ALERT_TOPIC=.*|HOMELAB_ALERT_TOPIC=${HOMELAB_ALERT_TOPIC}|' .env
else
  printf 'HOMELAB_ALERT_TOPIC=%s\n' '${HOMELAB_ALERT_TOPIC}' >> .env
fi
docker compose config -q
docker compose up -d prometheus alertmanager ntfy alert-forwarder
"

cat >"$SYNC_DIR/homelab-onions.conf" <<'EOF'
HiddenServiceDir /var/lib/tor/homelab-homepage/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:10080

HiddenServiceDir /var/lib/tor/homelab-vaultwarden/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:10081

HiddenServiceDir /var/lib/tor/homelab-linkding/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:10082

HiddenServiceDir /var/lib/tor/homelab-miniflux/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:10083

HiddenServiceDir /var/lib/tor/homelab-paperless/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:10084

HiddenServiceDir /var/lib/tor/homelab-stirling/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:10085

HiddenServiceDir /var/lib/tor/homelab-gitea/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:10086

HiddenServiceDir /var/lib/tor/homelab-actual/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:10087

HiddenServiceDir /var/lib/tor/homelab-filebrowser/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:10088

HiddenServiceDir /var/lib/tor/homelab-grafana/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:10089

HiddenServiceDir /var/lib/tor/homelab-uptime/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:10090

HiddenServiceDir /var/lib/tor/homelab-alerts/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:10091
EOF

pct push 201 "$SYNC_DIR/tor-edge-Caddyfile" /etc/caddy/Caddyfile
pct push 201 "$SYNC_DIR/homelab-onions.conf" /etc/tor/torrc.d/homelab-onions.conf
pct push 201 "$SYNC_DIR/homelab-onion-selftest.sh" /usr/local/sbin/homelab-onion-selftest.sh
pct exec 201 -- bash -lc '
set -euo pipefail
chmod 700 /usr/local/sbin/homelab-onion-selftest.sh
chown debian-tor:debian-tor /var/lib/tor/homelab-alerts 2>/dev/null || true
caddy validate --config /etc/caddy/Caddyfile
systemctl restart tor caddy
for _ in $(seq 1 30); do
  [[ -s /var/lib/tor/homelab-alerts/hostname ]] && break
  sleep 1
done
/usr/local/sbin/homelab-onion-selftest.sh
'

alerts_host="$(pct exec 201 -- sh -lc 'cat /var/lib/tor/homelab-alerts/hostname' | tr -d '\r\n')"
alerts_ui_url="http://${alerts_host}/app"

if [[ -n "$alerts_host" ]]; then
  cat >"$SECRETS_DIR/alerts-feed.txt" <<EOF
Alerts Feed
- Ntfy Web UI: ${alerts_ui_url}
- Topic: ${HOMELAB_ALERT_TOPIC}
EOF
  chmod 600 "$SECRETS_DIR/alerts-feed.txt"

  python3 - "$SECRETS_DIR/service-credentials.txt" "$alerts_ui_url" "$HOMELAB_ALERT_TOPIC" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
ui_url = sys.argv[2]
topic = sys.argv[3]
text = path.read_text(encoding="utf-8")
marker = "Alerts Feed\n"
start = text.find(marker)
if start != -1:
    end = text.find("\n\n", start)
    if end == -1:
        text = text[:start].rstrip() + "\n"
    else:
        text = text[:start].rstrip() + text[end:]
text = text.rstrip() + f"\n\nAlerts Feed\n- Ntfy Web UI: {ui_url}\n- Topic: {topic}\n"
path.write_text(text, encoding="utf-8")
PY
  chmod 600 "$SECRETS_DIR/service-credentials.txt"
fi

install -m 0700 "$SYNC_DIR/homelab-backup.sh" /usr/local/sbin/homelab-backup.sh
systemctl daemon-reload

pct push 202 "$SYNC_DIR/app-core-docker-compose.yml" /opt/homelab/app-core/docker-compose.yml
pct exec 202 -- bash -lc '
set -euo pipefail
cd /opt/homelab/app-core
if ! grep -q "^VAULTWARDEN_ADMIN_TOKEN=" .env || [[ -z "$(sed -n "s/^VAULTWARDEN_ADMIN_TOKEN=//p" .env | head -n1)" ]]; then
  echo "Vaultwarden admin token missing; leaving signups unchanged" >&2
  exit 0
fi
if grep -q "^VAULTWARDEN_SIGNUPS_ALLOWED=" .env 2>/dev/null; then
  sed -i "s|^VAULTWARDEN_SIGNUPS_ALLOWED=.*|VAULTWARDEN_SIGNUPS_ALLOWED=false|" .env
else
  printf "VAULTWARDEN_SIGNUPS_ALLOWED=false\n" >> .env
fi
docker compose config -q
docker compose up -d vaultwarden
'
upsert_env_file "$SECRETS_DIR/app-core.env" VAULTWARDEN_SIGNUPS_ALLOWED "false"

python3 - "$SECRETS_DIR/service-credentials.txt" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "Vaultwarden Bootstrap\n"
start = text.find(marker)
if start != -1:
    end = text.find("\n\n", start)
    if end == -1:
        text = text[:start].rstrip() + "\n"
    else:
        text = text[:start].rstrip() + text[end:]
text = text.rstrip() + "\n\nVaultwarden Bootstrap\n- Public signups are disabled.\n- Use the existing ADMIN_TOKEN at /admin on the Vaultwarden onion to invite the first user.\n"
path.write_text(text, encoding="utf-8")
PY
chmod 600 "$SECRETS_DIR/service-credentials.txt"
