#!/bin/bash
set -Eeuo pipefail

HOST_BRIDGE="vmbr90"
HOST_IP="172.31.90.1"
PROXY_PORT="3142"
NFT_TABLE="ailab_vmbr90"
IAC_ROOT="/root/ailab2-iac"
SECTION_ROOT="${IAC_ROOT}/section-03-config"
VALIDATION_DIR="${SECTION_ROOT}/validation"
MANIFEST_DIR="${SECTION_ROOT}/manifests"
PORTCHECK_DIR="${SECTION_ROOT}/port-checks"
TMP_ROOT="/root/ailab2-vm-fallback"

declare -A GUEST_NAME=(
  [201]="vm-apps-core"
  [202]="vm-apps-extended"
  [203]="vm-bitcoin-node"
  [204]="vm-bitcoin-service"
)

declare -A GUEST_FQDN=(
  [201]="vm-apps-core.apps.ailab.internal"
  [202]="vm-apps-extended.apps.ailab.internal"
  [203]="vm-bitcoin-node.bitcoin.ailab.internal"
  [204]="vm-bitcoin-service.bitcoin.ailab.internal"
)

declare -A GUEST_ZONE=(
  [201]="anwendungsdienste"
  [202]="anwendungsdienste"
  [203]="bitcoin-simulation"
  [204]="bitcoin-simulation"
)

declare -A GUEST_SRV_PATHS=(
  [201]="/srv/apps-core"
  [202]="/srv/apps-extended"
  [203]="/srv/bitcoin-sim/node"
  [204]="/srv/bitcoin-sim/service"
)

declare -A VM_TEMP_MAC=(
  [201]="BC:24:11:90:20:01"
  [202]="BC:24:11:90:20:02"
  [203]="BC:24:11:90:20:03"
  [204]="BC:24:11:90:20:04"
)

declare -A VM_TEMP_IP=(
  [201]="172.31.90.201"
  [202]="172.31.90.202"
  [203]="172.31.90.203"
  [204]="172.31.90.204"
)

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

cleanup_mount() {
  local mount_dir="$1"
  local loopdev="$2"
  set +e
  mountpoint -q "${mount_dir}" && umount "${mount_dir}"
  [[ -n "${loopdev}" ]] && losetup -d "${loopdev}" >/dev/null 2>&1
  rm -rf "${mount_dir}"
}

ensure_host_temp_path() {
  ip link show "${HOST_BRIDGE}" >/dev/null 2>&1 || fail "${HOST_BRIDGE} is missing."
  nft list table inet "${NFT_TABLE}" >/dev/null 2>&1 || fail "nft table ${NFT_TABLE} is missing."
  ss -ltnp | grep -F "${HOST_IP}:${PROXY_PORT}" >/dev/null 2>&1 || fail "APT proxy listener missing."
}

wait_for_vm_stop() {
  local vmid="$1"
  local attempts=0
  while true; do
    local status
    status="$(qm status "${vmid}" | awk '{print $2}')"
    [[ "${status}" == "stopped" ]] && break
    attempts=$((attempts + 1))
    [[ "${attempts}" -gt 360 ]] && fail "VM ${vmid} did not reach stopped state."
    sleep 5
  done
}

mount_vm_root_rw() {
  local vmid="$1"
  local mount_dir="$2"
  local loopdev
  mkdir -p "${mount_dir}"
  loopdev="$(losetup --find --show -P "/dev/pve/vm-${vmid}-disk-0")"
  mount "${loopdev}p1" "${mount_dir}"
  printf '%s\n' "${loopdev}"
}

mount_vm_root_ro() {
  local vmid="$1"
  local mount_dir="$2"
  local loopdev
  mkdir -p "${mount_dir}"
  loopdev="$(losetup --find --show -P "/dev/pve/vm-${vmid}-disk-0")"
  mount -o ro "${loopdev}p1" "${mount_dir}"
  printf '%s\n' "${loopdev}"
}

write_vm_bootstrap() {
  local vmid="$1"
  local root_dir="$2"
  local name="${GUEST_NAME[${vmid}]}"
  local zone="${GUEST_ZONE[${vmid}]}"
  local fqdn="${GUEST_FQDN[${vmid}]}"
  local srv_paths="${GUEST_SRV_PATHS[${vmid}]}"
  local net0_mac
  net0_mac="$(qm config "${vmid}" | awk -F'[=,]' '/^net0:/{print $2}')"
  [[ -n "${net0_mac}" ]] || fail "Could not determine net0 MAC for VM ${vmid}."

  mkdir -p "${root_dir}/etc/cloud/cloud.cfg.d" \
           "${root_dir}/etc/systemd/network" \
           "${root_dir}/etc/systemd/system" \
           "${root_dir}/etc/systemd/system/multi-user.target.wants" \
           "${root_dir}/usr/local/sbin" \
           "${root_dir}/var/lib/ailab"

  cat > "${root_dir}/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg" <<'EOF'
network:
  config: disabled
EOF

  cat > "${root_dir}/etc/systemd/network/10-ailab-net0.network" <<EOF
[Match]
MACAddress=${net0_mac}

[Network]
DHCP=no
LinkLocalAddressing=no
IPv6AcceptRA=no
EOF

  cat > "${root_dir}/etc/systemd/network/10-ailab-net1.network" <<EOF
[Match]
MACAddress=${VM_TEMP_MAC[${vmid}]}

[Network]
DHCP=no
Address=${VM_TEMP_IP[${vmid}]}/24
LinkLocalAddressing=no
IPv6AcceptRA=no
EOF

  cat > "${root_dir}/usr/local/sbin/ailab-section3.sh" <<EOF
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

for _ in \$(seq 1 120); do
  if ip -4 addr show | grep -q '${VM_TEMP_IP[${vmid}]}/24'; then
    break
  fi
  sleep 2
done

ip -4 addr show | grep -q '${VM_TEMP_IP[${vmid}]}/24'

cat > /etc/apt/apt.conf.d/90ailab-provision-proxy <<'EOP'
Acquire::http::Proxy "http://${HOST_IP}:${PROXY_PORT}";
Acquire::https::Proxy "http://${HOST_IP}:${PROXY_PORT}";
EOP

apt-get update
apt-get -y --with-new-pkgs upgrade
apt-get install -y qemu-guest-agent cloud-guest-utils

root_src=\$(findmnt -no SOURCE /)
fs_type=\$(findmnt -no FSTYPE /)
partnum=\$(lsblk -no PARTN "\${root_src}" 2>/dev/null | head -n 1 || true)
pkname=\$(lsblk -no PKNAME "\${root_src}" 2>/dev/null | head -n 1 || true)
if [[ -n "\${partnum}" && -n "\${pkname}" ]]; then
  growpart "/dev/\${pkname}" "\${partnum}" || true
fi
case "\${fs_type}" in
  ext2|ext3|ext4) resize2fs "\${root_src}" || true ;;
  xfs) xfs_growfs / || true ;;
esac

ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
printf 'Etc/UTC\n' > /etc/timezone

install -d -m 0755 /etc/ailab /var/log/ailab /etc/systemd/journald.conf.d /var/lib/ailab
install -d -m 0700 /etc/ailab/secrets
for dir in ${srv_paths}; do
  install -d -m 0755 "\${dir}"
done

cat > /etc/systemd/journald.conf.d/ailab-limits.conf <<'EOJ'
[Journal]
SystemMaxUse=64M
RuntimeMaxUse=32M
SystemMaxFileSize=16M
EOJ

cat > /etc/ailab/README.md <<'EOR'
Section 03 baseline only.
- no app runtimes
- no real secrets
- no published services
EOR

cat > /etc/ailab/secrets/README.md <<'EOS'
No real secrets are allowed in this run.
Only placeholders or empty directories are allowed.
EOS

cat > /etc/ailab/guest-role.txt <<'EOG'
guest=${name}
zone=${zone}
fqdn=${fqdn}
EOG

grep -q '^127.0.1.1 ' /etc/hosts || printf '127.0.1.1 %s %s\n' '${fqdn}' '${name}' >> /etc/hosts
printf '%s\n' '${name}' > /etc/hostname

if [[ "${zone}" == "bitcoin-simulation" ]]; then
  cat > /etc/ailab/bitcoin-dummy-only.txt <<'EOB'
Dummy-only Bitcoin simulation host.
Forbidden in this run:
- real seeds
- real xprv
- wallet.dat
- productive private keys
- productive API keys
EOB
fi

systemctl restart systemd-journald || true
systemctl enable qemu-guest-agent || true
systemctl start qemu-guest-agent || true

{
  echo "guest=${name}"
  echo "proxy=${HOST_IP}:${PROXY_PORT}"
  for port in ${PROXY_PORT} 22 111 8006 3128; do
    if timeout 2 bash -lc ": </dev/tcp/${HOST_IP}/\${port}" >/dev/null 2>&1; then
      status="open"
    else
      status="blocked"
    fi
    echo "tcp/\${port}=\${status}"
  done
} > /var/log/ailab/vmbr90-port-checks.log

dpkg-query -W > /var/log/ailab/package-manifest.txt
touch /var/log/ailab/section-03-config.done
touch /var/lib/ailab/section3.done
rm -f /etc/apt/apt.conf.d/90ailab-provision-proxy
systemctl poweroff --no-wall || poweroff -f
EOF
  chmod 0755 "${root_dir}/usr/local/sbin/ailab-section3.sh"

  cat > "${root_dir}/etc/systemd/system/ailab-section3.service" <<'EOF'
[Unit]
Description=Ailab Section 03 VM Bootstrap
ConditionPathExists=!/var/lib/ailab/section3.done
After=systemd-networkd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ailab-section3.sh
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

  ln -sf /etc/systemd/system/ailab-section3.service "${root_dir}/etc/systemd/system/multi-user.target.wants/ailab-section3.service"
}

extract_vm_results() {
  local vmid="$1"
  local mount_dir="${TMP_ROOT}/mnt-${vmid}"
  local loopdev
  loopdev="$(mount_vm_root_ro "${vmid}" "${mount_dir}")"

  cp "${mount_dir}/var/log/ailab/package-manifest.txt" "${MANIFEST_DIR}/${vmid}-${GUEST_NAME[${vmid}]}-package-manifest.txt"
  cp "${mount_dir}/var/log/ailab/vmbr90-port-checks.log" "${PORTCHECK_DIR}/${vmid}-${GUEST_NAME[${vmid}]}-vmbr90.txt"
  cp "${mount_dir}/var/log/ailab/section-03-config.done" "${VALIDATION_DIR}/${vmid}-section3-done.txt"
  df -h "${mount_dir}" > "${VALIDATION_DIR}/${vmid}-${GUEST_NAME[${vmid}]}-rootfs.txt"

  cleanup_mount "${mount_dir}" "${loopdev}"
}

cleanup_host_temp_path() {
  log "Cleaning up host temporary provisioning path."
  for vmid in 201 202 203 204; do
    qm status "${vmid}" | grep -q running && qm stop "${vmid}" >/dev/null 2>&1
    qm config "${vmid}" | grep -q '^net1:' && qm set "${vmid}" -delete net1 >/dev/null 2>&1
    qm config "${vmid}" | grep -q '^ide2:' && qm set "${vmid}" -delete ide2 >/dev/null 2>&1
  done

  systemctl stop apt-cacher-ng >/dev/null 2>&1 || true
  if dpkg-query -W -f='${Status}' apt-cacher-ng 2>/dev/null | grep -q 'install ok installed'; then
    DEBIAN_FRONTEND=noninteractive apt-get purge -y apt-cacher-ng >/dev/null 2>&1 || true
    apt-get clean >/dev/null 2>&1 || true
  fi

  nft list table inet "${NFT_TABLE}" >/dev/null 2>&1 && nft delete table inet "${NFT_TABLE}" >/dev/null 2>&1 || true
  ip link show "${HOST_BRIDGE}" >/dev/null 2>&1 && ip link set "${HOST_BRIDGE}" down >/dev/null 2>&1 || true
  ip link show "${HOST_BRIDGE}" >/dev/null 2>&1 && ip link delete "${HOST_BRIDGE}" type bridge >/dev/null 2>&1 || true
}

create_snapshots_and_validation() {
  log "Creating post-config-base snapshots after VM fallback."
  for ctid in 101 102 103 104; do
    pct listsnapshot "${ctid}" | grep -q post-config-base || pct snapshot "${ctid}" post-config-base
  done
  for vmid in 201 202 203 204; do
    qm listsnapshot "${vmid}" | grep -q post-config-base || qm snapshot "${vmid}" post-config-base
  done

  ! ip link show "${HOST_BRIDGE}" >/dev/null 2>&1
  ! nft list table inet "${NFT_TABLE}" >/dev/null 2>&1
  ! ss -ltnp | grep -F "${HOST_IP}:${PROXY_PORT}" >/dev/null 2>&1

  qm list > "${VALIDATION_DIR}/qm-list.txt"
  pct list > "${VALIDATION_DIR}/pct-list.txt"
  pvesm status > "${VALIDATION_DIR}/pvesm-status.txt"
  for vmid in 201 202 203 204; do
    qm config "${vmid}" > "${VALIDATION_DIR}/${vmid}-final-config.txt"
    qm listsnapshot "${vmid}" > "${VALIDATION_DIR}/${vmid}-snapshots.txt"
  done
  for ctid in 101 102 103 104; do
    pct config "${ctid}" > "${VALIDATION_DIR}/${ctid}-final-config.txt"
    pct listsnapshot "${ctid}" > "${VALIDATION_DIR}/${ctid}-snapshots.txt"
  done
  echo "apt-cacher-ng=absent" > "${VALIDATION_DIR}/host-proxy-package-state.txt"
}

process_vm() {
  local vmid="$1"
  local mount_dir="${TMP_ROOT}/mnt-${vmid}"
  local loopdev=""

  log "Rolling back VM ${vmid} (${GUEST_NAME[${vmid}]}) to post-provision-base."
  qm stop "${vmid}" >/dev/null 2>&1 || true
  wait_for_vm_stop "${vmid}"
  qm unlock "${vmid}" >/dev/null 2>&1 || true
  qm config "${vmid}" | grep -q '^net1:' && qm set "${vmid}" -delete net1 >/dev/null 2>&1 || true
  qm config "${vmid}" | grep -q '^ide2:' && qm set "${vmid}" -delete ide2 >/dev/null 2>&1 || true
  qm rollback "${vmid}" post-provision-base
  qm set "${vmid}" --agent 1
  qm set "${vmid}" --net1 "virtio=${VM_TEMP_MAC[${vmid}]},bridge=${HOST_BRIDGE}"

  log "Injecting offline bootstrap for VM ${vmid}."
  loopdev="$(mount_vm_root_rw "${vmid}" "${mount_dir}")"
  write_vm_bootstrap "${vmid}" "${mount_dir}"
  cleanup_mount "${mount_dir}" "${loopdev}"
  loopdev=""

  log "Starting VM ${vmid} for bootstrap execution."
  qm start "${vmid}"
  wait_for_vm_stop "${vmid}"
  extract_vm_results "${vmid}"
  qm set "${vmid}" -delete net1
}

main() {
  mkdir -p "${TMP_ROOT}" "${VALIDATION_DIR}" "${MANIFEST_DIR}" "${PORTCHECK_DIR}"
  ensure_host_temp_path

  process_vm 201
  process_vm 202
  process_vm 203
  process_vm 204

  cleanup_host_temp_path
  create_snapshots_and_validation
  log "VM fallback completed successfully."
}

main "$@"
