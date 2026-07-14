#!/usr/bin/env bash
set -euo pipefail

echo "ALL_LOCAL_ONION_PROXIES"
pct exec 201 -- bash -lc '
for pair in homepage:10080 vaultwarden:10081 linkding:10082 miniflux:10083 paperless:10084 stirling:10085 gitea:10086 actual:10087 filebrowser:10088 grafana:10089 uptime:10090 alerts:10091; do
  service="${pair%%:*}"
  port="${pair##*:}"
  host="$(cat /var/lib/tor/homelab-${service}/hostname)"
  code="$(curl --max-time 10 -H "Host: ${host}" -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${port}" || true)"
  echo "${service} ${code}"
done
'
