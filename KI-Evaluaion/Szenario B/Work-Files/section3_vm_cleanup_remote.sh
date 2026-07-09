#!/bin/bash
set -Eeuo pipefail

VMID="${VMID:-201}"
DISK_PATH="$(readlink -f "/dev/pve/vm-${VMID}-disk-0" 2>/dev/null || true)"

for pid in $(pgrep -f '/root/ailab2-vm-fallback|/root/ailab2-vm-chroot' || true); do
  kill "${pid}" || true
done
sleep 1
for pid in $(pgrep -f '/root/ailab2-vm-fallback|/root/ailab2-vm-chroot' || true); do
  kill -9 "${pid}" || true
done

for mount_path in \
  "/root/ailab2-vm-chroot/mnt-${VMID}-rw/dev/pts" \
  "/root/ailab2-vm-chroot/mnt-${VMID}-rw/boot/efi" \
  "/root/ailab2-vm-chroot/mnt-${VMID}-rw/run" \
  "/root/ailab2-vm-chroot/mnt-${VMID}-rw/sys" \
  "/root/ailab2-vm-chroot/mnt-${VMID}-rw/proc" \
  "/root/ailab2-vm-chroot/mnt-${VMID}-rw/dev" \
  "/root/ailab2-vm-chroot/mnt-${VMID}-rw" \
  "/root/ailab2-vm-chroot/mnt-${VMID}-ro"
do
  mountpoint -q "${mount_path}" && umount "${mount_path}" || true
done

while read -r loopdev; do
  [[ -n "${loopdev}" ]] || continue
  losetup -d "${loopdev}" || true
done < <(
  losetup -l -O NAME,BACK-FILE | awk -v pve_path="/dev/pve/vm-${VMID}-disk-0" -v dm_path="${DISK_PATH}" '
    $2 == pve_path || (dm_path != "" && $2 == dm_path) { print $1 }
  '
)

rm -rf /root/ailab2-vm-chroot
qm stop "${VMID}" >/dev/null 2>&1 || true
qm unlock "${VMID}" >/dev/null 2>&1 || true
qm config "${VMID}" | grep -q '^net1:' && qm set "${VMID}" -delete net1 >/dev/null 2>&1 || true
qm config "${VMID}" | grep -q '^ide2:' && qm set "${VMID}" -delete ide2 >/dev/null 2>&1 || true

qm status "${VMID}"
losetup -a || true
pgrep -af '/root/ailab2-vm-fallback|/root/ailab2-vm-chroot' || true
