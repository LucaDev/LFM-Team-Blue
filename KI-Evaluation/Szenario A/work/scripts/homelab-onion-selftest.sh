#!/usr/bin/env bash
set -euo pipefail

TEXTFILE_DIR=/var/lib/prometheus/node-exporter-textfile
OUTPUT_FILE="$TEXTFILE_DIR/homelab_onion.prom"
TMP_FILE="$(mktemp "$TEXTFILE_DIR/homelab_onion.prom.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

install -d -m 0755 "$TEXTFILE_DIR"

declare -A ports=(
  [homepage]=10080
  [vaultwarden]=10081
  [linkding]=10082
  [miniflux]=10083
  [paperless]=10084
  [stirling]=10085
  [gitea]=10086
  [actual]=10087
  [filebrowser]=10088
  [grafana]=10089
  [uptime]=10090
  [alerts]=10091
)

declare -A expected_statuses=(
  [homepage]="200"
  [vaultwarden]="200"
  [linkding]="301 302"
  [miniflux]="200"
  [paperless]="301 302"
  [stirling]="401"
  [gitea]="200"
  [actual]="200"
  [filebrowser]="200"
  [grafana]="301 302"
  [uptime]="301 302"
  [alerts]="200"
)

{
  echo '# HELP homelab_tor_hidden_service_up Local tor-edge proxy check against the expected HTTP status.'
  echo '# TYPE homelab_tor_hidden_service_up gauge'
  echo '# HELP homelab_tor_hidden_service_http_status Last HTTP status observed by the tor-edge local proxy check.'
  echo '# TYPE homelab_tor_hidden_service_http_status gauge'
  echo '# HELP homelab_tor_hidden_service_check_timestamp_seconds Unix timestamp of the last tor-edge self-test run.'
  echo '# TYPE homelab_tor_hidden_service_check_timestamp_seconds gauge'
  printf 'homelab_tor_hidden_service_check_timestamp_seconds %s\n' "$(date +%s)"

  for service in "${!ports[@]}"; do
    host_file="/var/lib/tor/homelab-${service}/hostname"
    status_code=0

    if [[ -r "$host_file" ]]; then
      hostname="$(tr -d '\r\n' <"$host_file")"
      status_code="$(curl --max-time 10 -s -o /dev/null -w '%{http_code}' -H "Host: ${hostname}" "http://127.0.0.1:${ports[$service]}" || true)"
    fi

    if [[ ! "$status_code" =~ ^[0-9]+$ ]]; then
      status_code=0
    fi

    service_up=0
    for accepted in ${expected_statuses[$service]}; do
      if [[ "$status_code" == "$accepted" ]]; then
        service_up=1
        break
      fi
    done

    printf 'homelab_tor_hidden_service_up{service="%s"} %s\n' "$service" "$service_up"
    printf 'homelab_tor_hidden_service_http_status{service="%s"} %s\n' "$service" "$status_code"
  done
} >"$TMP_FILE"

chmod 0644 "$TMP_FILE"
mv "$TMP_FILE" "$OUTPUT_FILE"
