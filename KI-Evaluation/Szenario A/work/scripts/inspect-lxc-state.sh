#!/usr/bin/env bash
set -euo pipefail

echo "HOST_TIME"
date
uptime -s
who -b || true
echo

echo "PCT_PROCESSES"
ps -ef | egrep 'pct|lxc-start|lxc-stop|pve-container' | grep -v grep || true
echo

echo "LOCKS"
ls -l /run/lock/lxc 2>/dev/null || true
echo

for unit in 201 202 203 204; do
  echo "SYSTEMD_UNIT_$unit"
  systemctl status "pve-container@$unit" --no-pager -l || true
  echo
done

for ctid in 201 202 203 204; do
  echo "LXC_INFO_$ctid"
  timeout 5 lxc-info -n "$ctid" || true
  echo
done

for ctid in 201 202 203 204; do
  echo "LXC_ATTACH_$ctid"
  timeout 10 lxc-attach -n "$ctid" -- sh -lc 'hostname; ip -br a' || true
  echo
done
