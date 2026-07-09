#!/bin/bash
set -Eeuo pipefail

chmod 0755 /root/ailab2-iac/section-03-config/scripts/section3_vm_chroot_remote.sh
for id in 201 202 203 204; do
  qm stop "${id}" >/dev/null 2>&1 || true
  qm unlock "${id}" >/dev/null 2>&1 || true
done

LOG="/root/ailab2-iac/section-03-config/logs/run-$(date -u +%Y%m%dT%H%M%SZ)-vm-chroot.log"
echo "log=${LOG}"
/root/ailab2-iac/section-03-config/scripts/section3_vm_chroot_remote.sh 2>&1 | tee "${LOG}"
