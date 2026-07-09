#!/usr/bin/env bash
set -euo pipefail

for pid in 1154 1155 1161 1982 1983 1987; do
  kill -9 "$pid" 2>/dev/null || true
done

rm -f /run/lock/lxc/pve-config-201.lock /run/lock/lxc/pve-config-202.lock
umount -lf /var/lib/lxc/.pve-staged-mounts/rootfs 2>/dev/null || true

for dev in /dev/pve/vm-201-disk-0 /dev/pve/vm-202-disk-0; do
  echo "CLEAR_MMP $dev"
  tune2fs -f -E clear_mmp "$dev"
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

for unit in 201 202 203; do
  echo "ATTACH $unit"
  timeout 15 lxc-attach -n "$unit" -- sh -lc 'hostname; ip -br a' || true
  echo
done
