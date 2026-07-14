#!/usr/bin/env bash
set -euo pipefail

echo "HOST_FIREWALL"
systemctl is-active nftables
nft list ruleset
echo

echo "HOST_RPCBIND"
systemctl is-enabled rpcbind.service rpcbind.socket || true
systemctl is-active rpcbind.service rpcbind.socket || true
echo

echo "HOST_MGMT_EXPOSURE"
for ct in 201 202 203 204; do
  pct exec "$ct" -- bash -lc '
for target in 10.10.10.1:22 10.10.10.1:8006 10.10.10.1:3128 10.10.10.1:111 10.10.20.1:22 10.10.20.1:8006 10.10.20.1:3128 10.10.20.1:111; do
  host="${target%:*}"
  port="${target#*:}"
  if timeout 2 bash -lc "</dev/tcp/${host}/${port}" >/dev/null 2>&1; then
    echo "'"$ct"' can reach ${target}"
  else
    echo "'"$ct"' blocked from ${target}"
  fi
done
'
  echo
done

echo "OPS_ALERTING"
pct exec 203 -- bash -lc '
cd /opt/homelab/ops
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "alertmanager|ntfy|alert-forwarder"
curl -sf http://127.0.0.1:2586/ >/dev/null
'
echo

echo "TOR_ALERTS_ONION"
pct exec 201 -- bash -lc '
host="$(cat /var/lib/tor/homelab-alerts/hostname)"
code="$(curl --max-time 10 -H "Host: ${host}" -s -o /dev/null -w "%{http_code}" http://127.0.0.1:10091/app || true)"
echo "${host} ${code}"
'
echo

echo "ALERTMANAGER_TO_NTFY_TEST"
topic="$(sed -n 's/^HOMELAB_ALERT_TOPIC=//p' /root/homelab-secrets/alerts-topic.env)"
pct exec 203 -- bash -lc '
docker exec ops-alert-forwarder-1 python - <<'\''PY'\''
import json
import urllib.request

payload = {
    "status": "firing",
    "alerts": [
        {
            "status": "firing",
            "labels": {
                "alertname": "ManualRemediationTest",
                "severity": "warning",
                "instance": "ops-test",
                "job": "manual",
            },
            "annotations": {
                "summary": "Manual remediation test",
                "description": "Verifies local alert delivery to ntfy.",
            },
        }
    ],
    "commonLabels": {
        "alertname": "ManualRemediationTest",
        "severity": "warning",
    },
    "commonAnnotations": {
        "summary": "Manual remediation test",
        "description": "Verifies local alert delivery to ntfy.",
    },
    "externalURL": "http://127.0.0.1:9093",
}
req = urllib.request.Request(
    "http://127.0.0.1:8088/alertmanager",
    data=json.dumps(payload).encode("utf-8"),
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(req, timeout=10) as response:
    print(response.status)
PY
'
sleep 2
pct exec 203 -- bash -lc "curl -s http://127.0.0.1:2586/${topic}/json?poll=1 | grep -F 'Manual remediation test' | tail -n 1"
echo

echo "BACKUP_SCRIPT"
bash -n /usr/local/sbin/homelab-backup.sh
systemctl start homelab-backup.service
systemctl --no-pager --full status homelab-backup.service
echo

echo "VAULTWARDEN_SIGNUPS"
pct exec 202 -- bash -lc 'cd /opt/homelab/app-core && docker inspect app-core-vaultwarden-1 --format "{{range .Config.Env}}{{println .}}{{end}}" | grep -E "SIGNUPS_ALLOWED|INVITATIONS_ALLOWED|ADMIN_TOKEN"'
