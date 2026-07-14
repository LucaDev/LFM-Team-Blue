#!/usr/bin/env bash
set -euo pipefail

STAGING_DIR=/root/homelab-staging
SECRETS_DIR=/root/homelab-secrets

mkdir -p "$SECRETS_DIR"
umask 077

gen_pw() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
  printf '\n'
}

gen_token() {
  openssl rand -hex 32
}

write_app_env() {
  local file="$SECRETS_DIR/app-core.env"
  if [[ -f "$file" ]]; then
    return
  fi

  cat >"$file" <<EOF
POSTGRES_PASSWORD=$(gen_pw)
VAULTWARDEN_ADMIN_TOKEN=$(gen_token)
LINKDING_SUPERUSER_NAME=admin
LINKDING_SUPERUSER_PASSWORD=$(gen_pw)
MINIFLUX_DB_PASSWORD=$(gen_pw)
MINIFLUX_ADMIN_USERNAME=admin
MINIFLUX_ADMIN_PASSWORD=$(gen_pw)
PAPERLESS_DB_PASSWORD=$(gen_pw)
PAPERLESS_SECRET_KEY=$(gen_token)
PAPERLESS_ADMIN_USER=admin
PAPERLESS_ADMIN_PASSWORD=$(gen_pw)
HOMEPAGE_ALLOWED_HOSTS=10.10.10.10,10.10.20.10,127.0.0.1,localhost
VAULTWARDEN_DOMAIN=http://10.10.10.10:8080
MINIFLUX_BASE_URL=http://10.10.10.10:8081
PAPERLESS_URL=http://10.10.10.10:8000
GITEA_ADMIN_USER=gitadmin
GITEA_ADMIN_PASSWORD=$(gen_pw)
GITEA_SECRET_KEY=$(gen_token)
GITEA_INTERNAL_TOKEN=$(gen_token)
GITEA_JWT_SECRET=$(gen_token)
GITEA_DOMAIN=10.10.10.10
GITEA_ROOT_URL=http://10.10.10.10:3001/
FILEBROWSER_ADMIN_USER=admin
FILEBROWSER_ADMIN_PASSWORD=$(gen_pw)
EOF
}

write_ops_env() {
  local file="$SECRETS_DIR/ops.env"
  if [[ -f "$file" ]]; then
    return
  fi

  cat >"$file" <<EOF
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$(gen_pw)
EOF
}

write_credentials_summary() {
  # shellcheck disable=SC1091
  source "$SECRETS_DIR/app-core.env"
  # shellcheck disable=SC1091
  source "$SECRETS_DIR/ops.env"

  cat >"$SECRETS_DIR/service-credentials.txt" <<EOF
Internal service URLs
- Homepage: http://10.10.10.10:3000
- Vaultwarden: http://10.10.10.10:8080
- Linkding: http://10.10.10.10:9090
- Miniflux: http://10.10.10.10:8081
- Paperless-ngx: http://10.10.10.10:8000
- Stirling PDF: http://10.10.10.10:8082
- Gitea: http://10.10.10.10:3001
- Actual Budget: http://10.10.10.10:5006
- File Browser: http://10.10.10.10:8083
- Grafana: http://10.10.20.20:3000
- Prometheus: http://10.10.20.20:9090
- Uptime Kuma: http://10.10.20.20:3001
- Alertmanager: http://10.10.20.20:9093
- Loki: http://10.10.20.20:3100

Admin and setup data
- Vaultwarden admin token: $VAULTWARDEN_ADMIN_TOKEN
- Vaultwarden first-user signup is temporarily enabled on the internal network.
- Linkding admin: $LINKDING_SUPERUSER_NAME / $LINKDING_SUPERUSER_PASSWORD
- Miniflux admin: $MINIFLUX_ADMIN_USERNAME / $MINIFLUX_ADMIN_PASSWORD
- Paperless admin: $PAPERLESS_ADMIN_USER / $PAPERLESS_ADMIN_PASSWORD
- Gitea admin: $GITEA_ADMIN_USER / $GITEA_ADMIN_PASSWORD
- File Browser admin: $FILEBROWSER_ADMIN_USER / $FILEBROWSER_ADMIN_PASSWORD
- Grafana admin: $GRAFANA_ADMIN_USER / $GRAFANA_ADMIN_PASSWORD
- Uptime Kuma still requires its first-run setup in the UI.
- Actual Budget creates its first account on first use.
EOF
}

deploy_tor_edge() {
  pct exec 201 -- bash -lc "$(cat <<'EOS'
set -euo pipefail
cat >/etc/caddy/Caddyfile <<'EOF'
{
  admin off
  auto_https off
}

:80 {
  respond "tor-edge ready; Tor publishing and reverse proxy routing are configured in the later network section." 200
}
EOF
systemctl restart caddy tor prometheus-node-exporter
systemctl is-active caddy tor prometheus-node-exporter
EOS
)"
}

deploy_app_core() {
  tar -C "$STAGING_DIR" -czf "$STAGING_DIR/app-core.tar.gz" app-core
  pct push 202 "$STAGING_DIR/app-core.tar.gz" /root/app-core.tar.gz
  pct push 202 "$SECRETS_DIR/app-core.env" /root/app-core.env

  pct exec 202 -- bash -lc "$(cat <<'EOS'
set -euo pipefail
mkdir -p /opt/homelab
rm -rf /opt/homelab/app-core
tar -xzf /root/app-core.tar.gz -C /opt/homelab
cp /root/app-core.env /opt/homelab/app-core/.env

# shellcheck disable=SC1091
source /root/app-core.env
cd /opt/homelab/app-core

sed -i "s/__MINIFLUX_DB_PASSWORD__/${MINIFLUX_DB_PASSWORD}/g" initdb/01-init.sql
sed -i "s/__PAPERLESS_DB_PASSWORD__/${PAPERLESS_DB_PASSWORD}/g" initdb/01-init.sql

mkdir -p \
  data/postgres \
  data/redis \
  data/vaultwarden \
  data/linkding \
  data/paperless/data \
  data/paperless/media \
  data/paperless/export \
  data/paperless/consume \
  data/gitea/gitea/conf \
  data/actual \
  data/filebrowser/srv \
  data/filebrowser/database

cat >data/gitea/gitea/conf/app.ini <<EOF
APP_NAME = AILab Git
RUN_MODE = prod
RUN_USER = git

[database]
DB_TYPE = sqlite3
PATH = /data/gitea/gitea.db

[server]
DOMAIN = ${GITEA_DOMAIN}
HTTP_PORT = 3000
ROOT_URL = ${GITEA_ROOT_URL}
SSH_DOMAIN = ${GITEA_DOMAIN}
DISABLE_SSH = true
OFFLINE_MODE = true

[security]
INSTALL_LOCK = true
SECRET_KEY = ${GITEA_SECRET_KEY}
INTERNAL_TOKEN = ${GITEA_INTERNAL_TOKEN}
PASSWORD_HASH_ALGO = pbkdf2

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = true

[oauth2]
JWT_SECRET = ${GITEA_JWT_SECRET}
EOF

chown -R 1000:1000 data/gitea data/paperless data/actual data/linkding data/filebrowser || true

docker compose pull
docker compose up -d

gitea_cid="$(docker compose ps -q gitea)"
if [[ -n "$gitea_cid" ]]; then
  for _ in $(seq 1 30); do
    if docker exec "$gitea_cid" gitea --version >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done
  docker exec "$gitea_cid" gitea admin user create \
    --admin \
    --username "$GITEA_ADMIN_USER" \
    --password "$GITEA_ADMIN_PASSWORD" \
    --email "$GITEA_ADMIN_USER@local.invalid" || true
fi

filebrowser_cid="$(docker compose ps -q filebrowser)"
if [[ -n "$filebrowser_cid" ]]; then
  for _ in $(seq 1 20); do
    if docker exec "$filebrowser_cid" filebrowser version >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  docker exec "$filebrowser_cid" filebrowser users update admin \
    --password "$FILEBROWSER_ADMIN_PASSWORD" \
    --database /database/filebrowser.db || \
  docker exec "$filebrowser_cid" filebrowser users add \
    "$FILEBROWSER_ADMIN_USER" \
    "$FILEBROWSER_ADMIN_PASSWORD" \
    --perm.admin \
    --database /database/filebrowser.db || true
fi

docker compose ps
EOS
)"
}

deploy_ops() {
  tar -C "$STAGING_DIR" -czf "$STAGING_DIR/ops.tar.gz" ops
  pct push 203 "$STAGING_DIR/ops.tar.gz" /root/ops.tar.gz
  pct push 203 "$SECRETS_DIR/ops.env" /root/ops.env

  pct exec 203 -- bash -lc "$(cat <<'EOS'
set -euo pipefail
mkdir -p /opt/homelab
rm -rf /opt/homelab/ops
tar -xzf /root/ops.tar.gz -C /opt/homelab
cp /root/ops.env /opt/homelab/ops/.env

cd /opt/homelab/ops
mkdir -p \
  data/prometheus \
  data/grafana \
  data/alertmanager \
  data/uptime-kuma \
  data/loki/chunks \
  data/loki/rules

chown -R 472:472 data/grafana || true

docker compose pull
docker compose up -d
docker compose ps
EOS
)"
}

write_app_env
write_ops_env
write_credentials_summary
deploy_tor_edge
deploy_app_core
deploy_ops
