#!/usr/bin/env bash
set -euo pipefail

SYNC_DIR=/root/homelab-config-sync
STAGING_DIR=/root/homelab-staging
SECRETS_DIR=/root/homelab-secrets

required_files=(
  "$SYNC_DIR/app-core-docker-compose.yml"
  "$SYNC_DIR/tor-edge-Caddyfile"
  "$SYNC_DIR/homepage-onion-template.yaml"
  "$SYNC_DIR/app-core-firewall.sh"
  "$SYNC_DIR/ops-firewall.sh"
  "$SYNC_DIR/homelab-docker-firewall.service"
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

read_onion_host() {
  local service="$1"
  pct exec 201 -- sh -lc "cat /var/lib/tor/homelab-${service}/hostname" | tr -d '\r\n'
}

install -d "$STAGING_DIR/app-core/config/homepage" "$STAGING_DIR/tor-edge"
install -m 0644 "$SYNC_DIR/app-core-docker-compose.yml" "$STAGING_DIR/app-core/docker-compose.yml"
install -m 0644 "$SYNC_DIR/homepage-onion-template.yaml" "$STAGING_DIR/app-core/config/homepage/services.onion-template.yaml"
install -m 0644 "$SYNC_DIR/tor-edge-Caddyfile" "$STAGING_DIR/tor-edge/Caddyfile"

if [[ -f "$SYNC_DIR/deploy-homelab-services.sh" ]]; then
  install -m 0700 "$SYNC_DIR/deploy-homelab-services.sh" /root/deploy-homelab-services.sh
fi

cat >"$SYNC_DIR/configure-tor-edge.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

backup_dir="/root/homelab-backups/network-tor-$(date +%Y%m%d-%H%M%S)"
install -d "$backup_dir" /etc/tor/torrc.d
cp -a /etc/caddy/Caddyfile "$backup_dir/Caddyfile.before" 2>/dev/null || true
cp -a /etc/tor/torrc "$backup_dir/torrc.before" 2>/dev/null || true
cp -a /etc/tor/torrc.d "$backup_dir/torrc.d.before" 2>/dev/null || true

grep -q '^%include /etc/tor/torrc.d/\*.conf$' /etc/tor/torrc || printf '\n%%include /etc/tor/torrc.d/*.conf\n' >> /etc/tor/torrc

for service in homepage vaultwarden linkding miniflux paperless stirling gitea actual filebrowser grafana uptime alerts; do
  install -d -m 0700 -o debian-tor -g debian-tor "/var/lib/tor/homelab-${service}"
done

cat >/etc/tor/torrc.d/homelab-onions.conf <<'TORCONF'
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
TORCONF

install -m 0644 /root/tor-edge-Caddyfile /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile
systemctl restart tor caddy

for service in homepage vaultwarden linkding miniflux paperless stirling gitea actual filebrowser grafana uptime alerts; do
  for _ in $(seq 1 30); do
    [[ -s "/var/lib/tor/homelab-${service}/hostname" ]] && break
    sleep 1
  done
done

systemctl is-active tor caddy
EOF

pct push 201 "$SYNC_DIR/tor-edge-Caddyfile" /root/tor-edge-Caddyfile
pct push 201 "$SYNC_DIR/configure-tor-edge.sh" /root/configure-tor-edge.sh
pct exec 201 -- bash -lc 'chmod 700 /root/configure-tor-edge.sh && /root/configure-tor-edge.sh'

homepage_host="$(read_onion_host homepage)"
vaultwarden_host="$(read_onion_host vaultwarden)"
linkding_host="$(read_onion_host linkding)"
miniflux_host="$(read_onion_host miniflux)"
paperless_host="$(read_onion_host paperless)"
stirling_host="$(read_onion_host stirling)"
gitea_host="$(read_onion_host gitea)"
actual_host="$(read_onion_host actual)"
filebrowser_host="$(read_onion_host filebrowser)"
grafana_host="$(read_onion_host grafana)"
uptime_host="$(read_onion_host uptime)"
alerts_host="$(read_onion_host alerts)"

homepage_url="http://${homepage_host}"
vaultwarden_url="http://${vaultwarden_host}"
linkding_url="http://${linkding_host}"
miniflux_url="http://${miniflux_host}"
paperless_url="http://${paperless_host}"
stirling_url="http://${stirling_host}"
gitea_url="http://${gitea_host}"
actual_url="http://${actual_host}"
filebrowser_url="http://${filebrowser_host}"
grafana_url="http://${grafana_host}"
uptime_url="http://${uptime_host}"
alerts_url="http://${alerts_host}"

rendered_services="$SYNC_DIR/rendered-homepage-services.yaml"
cp "$SYNC_DIR/homepage-onion-template.yaml" "$rendered_services"
sed -i \
  -e "s|__HOMEPAGE_ONION__|${homepage_url}|g" \
  -e "s|__VAULTWARDEN_ONION__|${vaultwarden_url}|g" \
  -e "s|__LINKDING_ONION__|${linkding_url}|g" \
  -e "s|__MINIFLUX_ONION__|${miniflux_url}|g" \
  -e "s|__PAPERLESS_ONION__|${paperless_url}|g" \
  -e "s|__STIRLING_ONION__|${stirling_url}|g" \
  -e "s|__GITEA_ONION__|${gitea_url}|g" \
  -e "s|__ACTUAL_ONION__|${actual_url}|g" \
  -e "s|__FILEBROWSER_ONION__|${filebrowser_url}|g" \
  -e "s|__GRAFANA_ONION__|${grafana_url}|g" \
  -e "s|__UPTIME_ONION__|${uptime_url}|g" \
  "$rendered_services"

upsert_env_file "$SECRETS_DIR/app-core.env" HOMEPAGE_ALLOWED_HOSTS "10.10.10.10,10.10.20.10,127.0.0.1,localhost,${homepage_host}"
upsert_env_file "$SECRETS_DIR/app-core.env" VAULTWARDEN_DOMAIN "${vaultwarden_url}"
upsert_env_file "$SECRETS_DIR/app-core.env" MINIFLUX_BASE_URL "${miniflux_url}"
upsert_env_file "$SECRETS_DIR/app-core.env" PAPERLESS_URL "${paperless_url}"
upsert_env_file "$SECRETS_DIR/app-core.env" GITEA_DOMAIN "${gitea_host}"
upsert_env_file "$SECRETS_DIR/app-core.env" GITEA_ROOT_URL "${gitea_url}/"

sed -i '/^Tor service URLs$/,$d' "$SECRETS_DIR/service-credentials.txt" 2>/dev/null || true

cat >"$SECRETS_DIR/onion-services.txt" <<EOF
Primary Tor entrypoint
- Homepage: ${homepage_url}

Direct service onions
- Vaultwarden: ${vaultwarden_url}
- Linkding: ${linkding_url}
- Miniflux: ${miniflux_url}
- Paperless-ngx: ${paperless_url}
- Stirling PDF: ${stirling_url}
- Gitea: ${gitea_url}
- Actual Budget: ${actual_url}
- File Browser: ${filebrowser_url}
- Grafana: ${grafana_url}
- Uptime Kuma: ${uptime_url}
- Alerts Feed: ${alerts_url}/app
EOF
chmod 600 "$SECRETS_DIR/onion-services.txt"

cat >>"$SECRETS_DIR/service-credentials.txt" <<EOF

Tor service URLs
- Homepage: ${homepage_url}
- Vaultwarden: ${vaultwarden_url}
- Linkding: ${linkding_url}
- Miniflux: ${miniflux_url}
- Paperless-ngx: ${paperless_url}
- Stirling PDF: ${stirling_url}
- Gitea: ${gitea_url}
- Actual Budget: ${actual_url}
- File Browser: ${filebrowser_url}
- Grafana: ${grafana_url}
- Uptime Kuma: ${uptime_url}
- Alerts Feed: ${alerts_url}/app
EOF
chmod 600 "$SECRETS_DIR/service-credentials.txt"

install -m 0644 "$SYNC_DIR/app-core-docker-compose.yml" "$STAGING_DIR/app-core/docker-compose.yml"
install -m 0644 "$rendered_services" "$STAGING_DIR/app-core/config/homepage/services.yaml"

cat >"$SYNC_DIR/apply-appcore-onion-config.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

cd /opt/homelab/app-core
timestamp="\$(date +%Y%m%d-%H%M%S)"
cp -a .env ".env.before-network-tor-\${timestamp}"
cp -a data/gitea/gitea/conf/app.ini "data/gitea/gitea/conf/app.ini.before-network-tor-\${timestamp}" 2>/dev/null || true

upsert_env() {
  local key="\$1"
  local value="\$2"
  if grep -q "^\${key}=" .env 2>/dev/null; then
    sed -i "s|^\${key}=.*|\${key}=\${value}|" .env
  else
    printf '%s=%s\n' "\$key" "\$value" >>.env
  fi
}

upsert_env HOMEPAGE_ALLOWED_HOSTS "10.10.10.10,10.10.20.10,127.0.0.1,localhost,${homepage_host}"
upsert_env VAULTWARDEN_DOMAIN "${vaultwarden_url}"
upsert_env MINIFLUX_BASE_URL "${miniflux_url}"
upsert_env PAPERLESS_URL "${paperless_url}"
upsert_env GITEA_DOMAIN "${gitea_host}"
upsert_env GITEA_ROOT_URL "${gitea_url}/"

# shellcheck disable=SC1091
source .env

cat >data/gitea/gitea/conf/app.ini <<APPINI
APP_NAME = AILab Git
RUN_MODE = prod
RUN_USER = git

[database]
DB_TYPE = sqlite3
PATH = /data/gitea/gitea.db

[server]
DOMAIN = \${GITEA_DOMAIN}
HTTP_PORT = 3000
ROOT_URL = \${GITEA_ROOT_URL}
SSH_DOMAIN = \${GITEA_DOMAIN}
DISABLE_SSH = true
OFFLINE_MODE = true

[security]
INSTALL_LOCK = true
SECRET_KEY = \${GITEA_SECRET_KEY}
INTERNAL_TOKEN = \${GITEA_INTERNAL_TOKEN}
PASSWORD_HASH_ALGO = pbkdf2

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = true

[oauth2]
JWT_SECRET = \${GITEA_JWT_SECRET}
APPINI

chown -R 1000:1000 data/gitea || true
docker compose config -q
docker compose up -d homepage vaultwarden miniflux paperless gitea

wait_http() {
  local name="\$1"
  local url="\$2"
  for _ in \$(seq 1 60); do
    code="\$(curl --max-time 5 -s -o /dev/null -w '%{http_code}' "\$url" || true)"
    if [[ "\$code" != "000" ]]; then
      echo "\$name \$code"
      return 0
    fi
    sleep 5
  done
  echo "\$name 000" >&2
  return 1
}

wait_http homepage http://127.0.0.1:3000
wait_http vaultwarden http://127.0.0.1:8080
wait_http miniflux http://127.0.0.1:8081
wait_http paperless http://127.0.0.1:8000
wait_http gitea http://127.0.0.1:3001
EOF

pct push 202 "$SYNC_DIR/app-core-docker-compose.yml" /opt/homelab/app-core/docker-compose.yml
pct push 202 "$rendered_services" /opt/homelab/app-core/config/homepage/services.yaml
pct push 202 "$SYNC_DIR/apply-appcore-onion-config.sh" /root/apply-appcore-onion-config.sh
pct exec 202 -- bash -lc 'chmod 700 /root/apply-appcore-onion-config.sh && /root/apply-appcore-onion-config.sh'

pct push 202 "$SYNC_DIR/app-core-firewall.sh" /usr/local/sbin/homelab-docker-firewall.sh
pct push 202 "$SYNC_DIR/homelab-docker-firewall.service" /etc/systemd/system/homelab-docker-firewall.service
pct exec 202 -- bash -lc 'chmod 700 /usr/local/sbin/homelab-docker-firewall.sh && systemctl daemon-reload && systemctl enable --now homelab-docker-firewall.service'

pct push 203 "$SYNC_DIR/ops-firewall.sh" /usr/local/sbin/homelab-docker-firewall.sh
pct push 203 "$SYNC_DIR/homelab-docker-firewall.service" /etc/systemd/system/homelab-docker-firewall.service
pct exec 203 -- bash -lc 'chmod 700 /usr/local/sbin/homelab-docker-firewall.sh && systemctl daemon-reload && systemctl enable --now homelab-docker-firewall.service'

echo "ONION_HTTP_CHECKS"
pct exec 201 -- bash -lc "for url in '${homepage_url}' '${vaultwarden_url}' '${grafana_url}' '${uptime_url}' '${alerts_url}/app'; do code=\$(curl --socks5-hostname 127.0.0.1:9050 --max-time 20 -s -o /dev/null -w '%{http_code}' \"\$url\" || true); echo \"\$url \$code\"; done"
echo

echo "DIRECT_ALLOWED_CHECKS"
pct exec 201 -- bash -lc 'for url in http://10.10.10.10:3000 http://10.10.20.20:3000; do code=$(curl --max-time 5 -s -o /dev/null -w "%{http_code}" "$url" || true); echo "$url $code"; done'
echo
pct exec 203 -- bash -lc 'for url in http://10.10.10.10:3000 http://10.10.10.10:8080; do code=$(curl --max-time 5 -s -o /dev/null -w "%{http_code}" "$url" || true); echo "$url $code"; done'
echo

echo "DIRECT_BLOCK_CHECKS"
pct exec 202 -- bash -lc 'for url in http://10.10.20.20:3000 http://10.10.20.20:3001 http://10.10.10.2:10080; do code=$(curl --max-time 5 -s -o /dev/null -w "%{http_code}" "$url" || true); echo "$url $code"; done'
echo

echo "FIREWALL_RULES_202"
pct exec 202 -- bash -lc 'iptables -S DOCKER-USER'
echo

echo "FIREWALL_RULES_203"
pct exec 203 -- bash -lc 'iptables -S DOCKER-USER'
