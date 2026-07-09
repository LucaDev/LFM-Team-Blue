#!/usr/bin/env bash
set -euo pipefail

echo "ONION_SUMMARY"
cat /root/homelab-secrets/onion-services.txt
echo

echo "TOR_EDGE_LISTENERS"
pct exec 201 -- sh -lc 'ss -tlnp'
echo

echo "TOR_EDGE_CADDYFILE"
pct exec 201 -- sh -lc 'cat /etc/caddy/Caddyfile'
echo

echo "LOCAL_PROXY_CHECKS"
pct exec 201 -- bash -lc '
for pair in homepage:10080 vaultwarden:10081 grafana:10089 uptime:10090 alerts:10091; do
  service="${pair%%:*}"
  port="${pair##*:}"
  host="$(cat /var/lib/tor/homelab-${service}/hostname)"
  code="$(curl --max-time 5 -H "Host: ${host}" -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${port}" || true)"
  echo "${service} ${host} ${code}"
done
'
echo

echo "APPCORE_ENV"
pct exec 202 -- sh -lc 'grep -E "^(HOMEPAGE_ALLOWED_HOSTS|VAULTWARDEN_DOMAIN|MINIFLUX_BASE_URL|PAPERLESS_URL|GITEA_DOMAIN|GITEA_ROOT_URL)=" /opt/homelab/app-core/.env'
