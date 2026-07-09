#!/usr/bin/env bash
set -euo pipefail

echo "NODE_EXPORTER_TEXTFILE"
pct exec 201 -- sh -lc 'cat /var/lib/prometheus/node-exporter-textfile/homelab_onion.prom'
echo

echo "PROMETHEUS_TOR_METRICS"
pct exec 203 -- sh -lc 'curl -sG --data-urlencode '\''query=homelab_tor_hidden_service_up'\'' http://127.0.0.1:9090/api/v1/query | jq -r '\''.data.result[] | [.metric.service, .value[1]] | @tsv'\'''
echo

echo "PROMETHEUS_PROBE_FAILURES"
pct exec 203 -- sh -lc 'curl -sG --data-urlencode '\''query=probe_success{job=~"blackbox-http-.*"} == 0'\'' http://127.0.0.1:9090/api/v1/query | jq -r '\''.data.result[] | [.metric.job, .metric.instance, .value[1]] | @tsv'\'''
echo

echo "PROMETHEUS_ALERTS"
pct exec 203 -- sh -lc 'curl -s http://127.0.0.1:9090/api/v1/alerts | jq -r '\''.data.alerts[]? | [.labels.alertname, (.labels.instance // .labels.service // "-"), .state] | @tsv'\'''
echo

echo "UPTIME_KUMA_COUNTS"
pct exec 203 -- sh -lc 'sqlite3 /opt/homelab/ops/data/uptime-kuma/kuma.db "select count(*) as users from user; select count(*) as monitors from monitor; select count(*) as notifications from notification;"'
echo

echo "BACKUP_TIMER"
systemctl is-enabled homelab-backup.timer
systemctl is-active homelab-backup.timer
systemctl show -p NextElapseUSecRealtime homelab-backup.timer
echo

echo "BACKUP_FILES"
find /var/lib/homelab-backups/runs -maxdepth 2 -type f \( -name 'vzdump-lxc-*.tar.zst' -o -name 'tor-edge-config-*.tar.gz' -o -name 'tor-edge-identities-*.tar.gz' -o -name 'btc-node-config-*.tar.gz' -o -name 'manifest.txt' -o -name 'run.log' \) | sort
