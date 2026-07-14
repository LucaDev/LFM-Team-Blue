#!/usr/bin/env bash
set -euo pipefail

echo "APP_CORE_HTTP"
pct exec 202 -- sh -lc 'for url in http://127.0.0.1:3000 http://127.0.0.1:8080 http://127.0.0.1:9090 http://127.0.0.1:8081 http://127.0.0.1:8000 http://127.0.0.1:8082 http://127.0.0.1:3001 http://127.0.0.1:5006 http://127.0.0.1:8083; do code=$(curl --max-time 5 -s -o /dev/null -w "%{http_code}" "$url" || true); echo "$url $code"; done'
echo

echo "APP_CORE_STATUS"
pct exec 202 -- sh -lc 'docker ps --format "table {{.Names}}\t{{.Status}}"'
echo

echo "APP_CORE_CONFIG"
pct exec 202 -- sh -lc 'docker inspect app-core-homepage-1 --format "{{range .Mounts}}{{println .Destination}}{{end}}"'
echo
pct exec 202 -- sh -lc 'docker inspect app-core-paperless-1 --format "{{range .Config.Env}}{{println .}}{{end}}" | grep PAPERLESS_ACCOUNT_ALLOW_SIGNUPS'
echo
pct exec 202 -- sh -lc 'docker inspect app-core-homepage-1 --format "{{range .Config.Env}}{{println .}}{{end}}" | egrep "HOMEPAGE_ALLOWED_HOSTS|TZ"'
echo

echo "OPS_HTTP"
pct exec 203 -- sh -lc 'for url in http://127.0.0.1:3000 http://127.0.0.1:9090 http://127.0.0.1:9093 http://127.0.0.1:3001 http://127.0.0.1:3100/ready http://127.0.0.1:9115; do code=$(curl --max-time 5 -s -o /dev/null -w "%{http_code}" "$url" || true); echo "$url $code"; done'
echo

echo "OPS_STATUS"
pct exec 203 -- sh -lc 'docker ps --format "table {{.Names}}\t{{.Status}}"'
echo

echo "OPS_GRAFANA_ENV"
pct exec 203 -- sh -lc 'docker inspect ops-grafana-1 --format "{{range .Config.Env}}{{println .}}{{end}}" | egrep "GF_USERS_ALLOW_SIGN_UP|GF_AUTH_ANONYMOUS_ENABLED|GF_SECURITY_DISABLE_GRAVATAR|GF_ANALYTICS_REPORTING_ENABLED|GF_ANALYTICS_CHECK_FOR_UPDATES|TZ"'
