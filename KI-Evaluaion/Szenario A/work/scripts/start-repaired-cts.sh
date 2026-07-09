#!/usr/bin/env bash
set -euo pipefail

rm -f /run/lock/lxc/pve-config-201.lock /run/lock/lxc/pve-config-202.lock

for unit in 201 202; do
  echo "START $unit"
  pct start "$unit"
  echo
done

sleep 5

for unit in 201 202 203; do
  echo "STATUS $unit"
  timeout 10 pct status "$unit" || true
  echo
done

for unit in 201 202 203; do
  echo "ATTACH $unit"
  timeout 15 lxc-attach -n "$unit" -- sh -lc 'hostname; ip -br a; systemctl is-active docker 2>/dev/null || true; systemctl is-active caddy 2>/dev/null || true; systemctl is-active tor 2>/dev/null || true' || true
  echo
done
