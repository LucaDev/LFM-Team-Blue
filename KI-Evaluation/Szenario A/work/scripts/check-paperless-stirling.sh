#!/usr/bin/env bash
set -euo pipefail

pct exec 202 -- sh -lc 'for url in http://127.0.0.1:8000 http://127.0.0.1:8082; do code=$(curl --max-time 5 -s -o /dev/null -w "%{http_code}" "$url" || true); echo "$url $code"; done'
echo

pct exec 202 -- sh -lc 'docker ps --format "table {{.Names}}\t{{.Status}}" | egrep "NAMES|paperless|stirling"'
echo

pct exec 202 -- sh -lc 'docker inspect app-core-stirling-pdf-1 --format "{{json .State.Health}}"'
