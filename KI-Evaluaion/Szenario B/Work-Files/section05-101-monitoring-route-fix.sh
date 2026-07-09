#!/bin/sh
set -eu

SECTION="/root/ailab2-iac/section-05-backup-monitoring"
LOGDIR="$SECTION/logs"
VALIDDIR="$SECTION/validation"

mkdir -p "$LOGDIR" "$VALIDDIR" "$SECTION/staging"

log() {
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOGDIR/section05-101-monitoring-route-fix.log"
}

write_file() {
  path="$1"
  shift
  tmp="${path}.tmp"
  umask 077
  cat >"$tmp"
  mv "$tmp" "$path"
}

log "Schreibe persistente Monitoring-Route in 101"
write_file "$SECTION/staging/101-interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
	address 10.0.2.101/24
	gateway 10.0.2.2

auto eth1
iface eth1 inet static
	address 10.10.10.10/24
	post-up ip route replace 10.30.30.0/24 via 10.10.10.1 dev eth1
	pre-down ip route del 10.30.30.0/24 via 10.10.10.1 dev eth1 || true
EOF
pct push 101 "$SECTION/staging/101-interfaces" /etc/network/interfaces >/dev/null

log "Setze Route live und erfasse Route-Status"
pct exec 101 -- ip route replace 10.30.30.0/24 via 10.10.10.1 dev eth1
pct exec 101 -- ip route >"$VALIDDIR/101-routes-after-monitoring-route.txt"
pct exec 101 -- cat /etc/network/interfaces >"$VALIDDIR/101-interfaces-after-monitoring-route.txt"

log "101-Monitoring-Route aktualisiert"
