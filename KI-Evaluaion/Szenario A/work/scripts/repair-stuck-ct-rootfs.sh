#!/usr/bin/env bash
set -euo pipefail

for unit in 201 202; do
  systemctl stop "pve-container@$unit" 2>/dev/null || true
  systemctl kill --kill-who=all -s KILL "pve-container@$unit" 2>/dev/null || true
done

pkill -f '/usr/sbin/pct list' 2>/dev/null || true
pkill -f '/usr/sbin/pct status' 2>/dev/null || true
pkill -f '/usr/sbin/pct start 202' 2>/dev/null || true
pkill -f '/usr/sbin/pct start 201' 2>/dev/null || true

rm -f /run/lock/lxc/pve-config-201.lock /run/lock/lxc/pve-config-202.lock
umount -lf /var/lib/lxc/.pve-staged-mounts/rootfs 2>/dev/null || true

for dev in /dev/pve/vm-201-disk-0 /dev/pve/vm-202-disk-0; do
  echo "FSCK $dev"
  e2fsck -fy "$dev"
  echo
done

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

for unit in 201 202; do
  echo "ATTACH $unit"
  timeout 15 lxc-attach -n "$unit" -- sh -lc 'hostname; ip -br a' || true
  echo
done
