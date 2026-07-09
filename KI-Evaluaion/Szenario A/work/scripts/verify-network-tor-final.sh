#!/usr/bin/env bash
set -euo pipefail

echo "ALLOWED_PATHS"
pct exec 201 -- sh -lc 'for url in http://10.10.10.10:3000 http://10.10.20.20:3000; do code=$(curl --max-time 5 -s -o /dev/null -w "%{http_code}" "$url" || true); echo "$url $code"; done'
echo
pct exec 203 -- sh -lc 'for url in http://10.10.10.10:3000 http://10.10.10.10:8080; do code=$(curl --max-time 5 -s -o /dev/null -w "%{http_code}" "$url" || true); echo "$url $code"; done'
echo

echo "BLOCKED_PATHS"
pct exec 202 -- sh -lc 'for url in http://10.10.20.20:3000 http://10.10.20.20:3001 http://10.10.10.2:10080; do code=$(curl --max-time 5 -s -o /dev/null -w "%{http_code}" "$url" || true); echo "$url $code"; done'
echo

echo "LOCAL_ONION_PROXY"
pct exec 201 -- bash -lc '
for pair in homepage:10080 vaultwarden:10081 grafana:10089 uptime:10090 alerts:10091; do
  service="${pair%%:*}"
  port="${pair##*:}"
  host="$(cat /var/lib/tor/homelab-${service}/hostname)"
  code="$(curl --max-time 5 -H "Host: ${host}" -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${port}" || true)"
  echo "${service} ${code}"
done
'
echo

echo "FIREWALL_RULES_202"
pct exec 202 -- sh -lc 'iptables -S HOMELAB-DOCKER-ACCESS'
echo

echo "FIREWALL_RULES_203"
pct exec 203 -- sh -lc 'iptables -S HOMELAB-DOCKER-ACCESS'
