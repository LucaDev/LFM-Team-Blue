#!/usr/bin/env bash
set -euo pipefail

echo "UPTIME_KUMA_DATA"
pct exec 203 -- sh -lc 'ls -la /opt/homelab/ops/data/uptime-kuma'
echo

echo "UPTIME_KUMA_CONTAINER"
pct exec 203 -- sh -lc 'docker ps --format "table {{.Names}}\t{{.Status}}" | grep uptime-kuma'
echo

echo "UPTIME_KUMA_DB"
pct exec 203 -- sh -lc '
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 /opt/homelab/ops/data/uptime-kuma/kuma.db ".tables" 2>/dev/null || true
else
  docker exec ops-uptime-kuma-1 sh -lc "sqlite3 /app/data/kuma.db \".tables\"" 2>/dev/null || true
fi
'
echo

echo "ALERTMANAGER_STATUS"
pct exec 203 -- sh -lc 'curl --max-time 5 -s http://127.0.0.1:9093/api/v2/status'
echo

echo "PROMETHEUS_RULES"
pct exec 203 -- sh -lc 'curl --max-time 5 -s http://127.0.0.1:9090/api/v1/rules'
