#!/usr/bin/env bash
set -euo pipefail

echo "PAPERLESS_HEALTH"
pct exec 202 -- sh -lc 'docker inspect app-core-paperless-1 --format "{{json .State.Health}}"'
echo

echo "PAPERLESS_LOGS"
pct exec 202 -- sh -lc 'docker logs --tail 80 app-core-paperless-1'
echo

echo "STIRLING_HEALTH"
pct exec 202 -- sh -lc 'docker inspect app-core-stirling-pdf-1 --format "{{json .State.Health}}"'
echo

echo "STIRLING_LOGS"
pct exec 202 -- sh -lc 'docker logs --tail 80 app-core-stirling-pdf-1'
