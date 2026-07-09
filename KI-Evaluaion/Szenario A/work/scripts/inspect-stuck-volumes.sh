#!/usr/bin/env bash
set -euo pipefail

echo "STUCK_PROCESSES"
ps -o pid,ppid,stat,wchan:32,cmd -p 1154,1155,1161,1982,1983,1987 2>/dev/null || true
echo

echo "STAGED_MOUNTS"
mount | egrep 'pve-staged-mounts|vm-20[12]-disk-0' || true
echo

for dev in /dev/pve/vm-201-disk-0 /dev/pve/vm-202-disk-0; do
  echo "DEVICE $dev"
  lsblk -f "$dev" || true
  tune2fs -l "$dev" 2>/dev/null | egrep 'Filesystem features|MMP|Last mount time|Last write time|State|Errors behavior' || true
  echo
done

echo "DMESG_RECENT"
dmesg | tail -n 60
