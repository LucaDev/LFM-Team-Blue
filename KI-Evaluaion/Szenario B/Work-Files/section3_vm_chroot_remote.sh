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
TMP_ROOT="/root/ailab2-vm-chroot"
VM_IDS="${VM_IDS:-201 202 203 204}"

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

record_host_temp_validation() {
  ip -4 addr show "${HOST_BRIDGE}" > "${VALIDATION_DIR}/vmbr90-ip.txt"
  ss -ltnp '( sport = :22 or sport = :111 or sport = :8006 or sport = :3128 or sport = :3142 )' > "${VALIDATION_DIR}/apt-proxy-listener.txt"
  nft list table inet "${NFT_TABLE}" > "${VALIDATION_DIR}/ailab_vmbr90.txt"
}

ensure_host_temp_path() {
  ip link show "${HOST_BRIDGE}" >/dev/null 2>&1 || fail "${HOST_BRIDGE} is missing."
  nft list table inet "${NFT_TABLE}" >/dev/null 2>&1 || fail "nft table ${NFT_TABLE} is missing."
  ss -ltnp | grep -F "${HOST_IP}:${PROXY_PORT}" >/dev/null 2>&1 || fail "APT proxy listener missing."
  record_host_temp_validation
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

cleanup_mount_tree() {
  local root_dir="$1"
  local loopdev="$2"
  set +e
  mountpoint -q "${root_dir}/dev/pts" && umount "${root_dir}/dev/pts"
  mountpoint -q "${root_dir}/boot/efi" && umount "${root_dir}/boot/efi"
  mountpoint -q "${root_dir}/run" && umount "${root_dir}/run"
  mountpoint -q "${root_dir}/sys" && umount "${root_dir}/sys"
  mountpoint -q "${root_dir}/proc" && umount "${root_dir}/proc"
  mountpoint -q "${root_dir}/dev" && umount "${root_dir}/dev"
  mountpoint -q "${root_dir}" && umount "${root_dir}"
  [[ -n "${loopdev}" ]] && losetup -d "${loopdev}" >/dev/null 2>&1
  rm -rf "${root_dir}"
}

resize_disk_if_needed() {
  local vmid="$1"
  local disk="/dev/pve/vm-${vmid}-disk-0"
  local total end start part_guid

  total="$(blockdev --getsz "${disk}")"
  end="$(partx -s "${disk}" | awk '$1==1 {print $3}')"
  start="$(partx -s "${disk}" | awk '$1==1 {print $2}')"
  part_guid="$(sgdisk -i 1 "${disk}" | awk -F': ' '/Partition unique GUID/{print $2}')"

  [[ -n "${end}" && -n "${start}" && -n "${part_guid}" ]] || fail "Could not inspect partition layout for VM ${vmid}."

  if (( end < total - 34 )); then
    log "Expanding GPT/root partition for VM ${vmid}."
    sgdisk -e "${disk}"
    sgdisk -d 1 -n "1:${start}:0" -u "1:${part_guid}" -t 1:8304 "${disk}"
  fi
}

mount_vm_rw() {
  local vmid="$1"
  local root_dir="$2"
  local loopdev
  mkdir -p "${root_dir}"
  resize_disk_if_needed "${vmid}"
  loopdev="$(losetup --find --show -P "/dev/pve/vm-${vmid}-disk-0")"
  e2fsck -pf "${loopdev}p1" >/dev/null 2>&1 || true
  resize2fs "${loopdev}p1" >/dev/null
  mount "${loopdev}p1" "${root_dir}"
  mkdir -p "${root_dir}/boot/efi" "${root_dir}/dev/pts"
  if [[ -b "${loopdev}p15" ]]; then
    mount "${loopdev}p15" "${root_dir}/boot/efi"
  fi
  mount --bind /dev "${root_dir}/dev"
  mount --bind /dev/pts "${root_dir}/dev/pts"
  mount --bind /proc "${root_dir}/proc"
  mount --bind /sys "${root_dir}/sys"
  mount --bind /run "${root_dir}/run"
  printf '%s\n' "${loopdev}"
}

mount_vm_ro() {
  local vmid="$1"
  local root_dir="$2"
  local loopdev
  mkdir -p "${root_dir}"
  loopdev="$(losetup --find --show -P "/dev/pve/vm-${vmid}-disk-0")"
  mount -o ro "${loopdev}p1" "${root_dir}"
  printf '%s\n' "${loopdev}"
}

write_network_and_validator() {
  local vmid="$1"
  local root_dir="$2"
  local name="${GUEST_NAME[${vmid}]}"
  local zone="${GUEST_ZONE[${vmid}]}"
  local fqdn="${GUEST_FQDN[${vmid}]}"
  local net0_mac

  net0_mac="$(qm config "${vmid}" | awk -F'[=,]' '/^net0:/{print $2}')"
  [[ -n "${net0_mac}" ]] || fail "Could not determine net0 MAC for VM ${vmid}."

  mkdir -p \
    "${root_dir}/etc/cloud/cloud.cfg.d" \
    "${root_dir}/etc/systemd/network" \
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

  cat > "${root_dir}/usr/local/sbin/ailab-vmbr90-validate.sh" <<EOF
#!/bin/bash
set -euo pipefail

for _ in \$(seq 1 120); do
  if ip -4 addr show | grep -q '${VM_TEMP_IP[${vmid}]}/24'; then
    break
  fi
  sleep 2
done

ip -4 addr show | grep -q '${VM_TEMP_IP[${vmid}]}/24'

install -d -m 0755 /var/log/ailab /var/lib/ailab
proxy_status="blocked"
for _ in \$(seq 1 30); do
  if timeout 2 bash -lc ": </dev/tcp/${HOST_IP}/${PROXY_PORT}" >/dev/null 2>&1; then
    proxy_status="open"
    break
  fi
  sleep 2
done

{
  echo "guest=${name}"
  echo "zone=${zone}"
  echo "fqdn=${fqdn}"
  echo "proxy=${HOST_IP}:${PROXY_PORT}"
  echo "tcp/${PROXY_PORT}=\${proxy_status}"
  for port in 22 111 8006 3128; do
    if timeout 2 bash -lc ": </dev/tcp/${HOST_IP}/\${port}" >/dev/null 2>&1; then
      status="open"
    else
      status="blocked"
    fi
    echo "tcp/\${port}=\${status}"
  done
} > /var/log/ailab/vmbr90-port-checks.log

touch /var/lib/ailab/vmbr90-validated.done
systemctl poweroff --no-wall || poweroff -f
EOF
  chmod 0755 "${root_dir}/usr/local/sbin/ailab-vmbr90-validate.sh"

  cat > "${root_dir}/etc/systemd/system/ailab-vmbr90-validate.service" <<'EOF'
[Unit]
Description=Ailab vmbr90 validator
ConditionPathExists=!/var/lib/ailab/vmbr90-validated.done
Wants=network-online.target systemd-networkd-wait-online.service
After=systemd-networkd.service systemd-networkd-wait-online.service network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ailab-vmbr90-validate.sh
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

  ln -sf /etc/systemd/system/ailab-vmbr90-validate.service "${root_dir}/etc/systemd/system/multi-user.target.wants/ailab-vmbr90-validate.service"
}

configure_vm_offline() {
  local vmid="$1"
  local root_dir="$2"
  local name="${GUEST_NAME[${vmid}]}"
  local zone="${GUEST_ZONE[${vmid}]}"
  local fqdn="${GUEST_FQDN[${vmid}]}"
  local srv_paths="${GUEST_SRV_PATHS[${vmid}]}"

  cat > "${root_dir}/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
  chmod 0755 "${root_dir}/usr/sbin/policy-rc.d"

  chroot "${root_dir}" /bin/bash -lc "
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    export LANG=C.UTF-8
    export LC_ALL=C.UTF-8

    cat > /etc/apt/apt.conf.d/90ailab-provision-proxy <<'EOP'
Acquire::http::Proxy \"http://${HOST_IP}:${PROXY_PORT}\";
Acquire::https::Proxy \"http://${HOST_IP}:${PROXY_PORT}\";
EOP

    apt-get update
    apt-get -y --with-new-pkgs upgrade
    apt-get install -y qemu-guest-agent cloud-guest-utils

    # Rootfs growth is completed offline before first boot; remove redundant growfs-on-boot.
    sed -i 's/,x-systemd.growfs//g' /etc/fstab

    ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
    printf 'Etc/UTC\n' > /etc/timezone
    install -d -m 0755 /etc/ailab /var/log/ailab /etc/systemd/journald.conf.d /var/lib/ailab
    install -d -m 0700 /etc/ailab/secrets
    for dir in ${srv_paths}; do
      install -d -m 0755 \"\$dir\"
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

    if [[ '${zone}' == 'bitcoin-simulation' ]]; then
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

    dpkg-query -W > /var/log/ailab/package-manifest.txt
    touch /var/log/ailab/section-03-config.done
    rm -f /etc/apt/apt.conf.d/90ailab-provision-proxy
  "

  rm -f "${root_dir}/usr/sbin/policy-rc.d"
  if [[ -f "${root_dir}/usr/lib/systemd/system/qemu-guest-agent.service" ]]; then
    ln -sf /usr/lib/systemd/system/qemu-guest-agent.service "${root_dir}/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service"
  fi

  write_network_and_validator "${vmid}" "${root_dir}"
}

extract_results() {
  local vmid="$1"
  local root_dir="${TMP_ROOT}/mnt-${vmid}-ro"
  local loopdev
  loopdev="$(mount_vm_ro "${vmid}" "${root_dir}")"

  cp "${root_dir}/var/log/ailab/package-manifest.txt" "${MANIFEST_DIR}/${vmid}-${GUEST_NAME[${vmid}]}-package-manifest.txt"
  cp "${root_dir}/var/log/ailab/vmbr90-port-checks.log" "${PORTCHECK_DIR}/${vmid}-${GUEST_NAME[${vmid}]}-vmbr90.txt"
  cp "${root_dir}/var/log/ailab/section-03-config.done" "${VALIDATION_DIR}/${vmid}-section3-done.txt"
  df -h "${root_dir}" > "${VALIDATION_DIR}/${vmid}-${GUEST_NAME[${vmid}]}-rootfs.txt"

  cleanup_mount_tree "${root_dir}" "${loopdev}"
}

cleanup_host_temp_path() {
  log "Cleaning up host temporary provisioning path."
  for vmid in 201 202 203 204; do
    qm status "${vmid}" | grep -q running && qm stop "${vmid}" >/dev/null 2>&1
    qm config "${vmid}" | grep -q '^net1:' && qm set "${vmid}" -delete net1 >/dev/null 2>&1 || true
    qm config "${vmid}" | grep -q '^ide2:' && qm set "${vmid}" -delete ide2 >/dev/null 2>&1 || true
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

create_final_validation() {
  log "Creating post-config-base snapshots after chroot fallback."
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
  ip -br link show type bridge > "${VALIDATION_DIR}/host-bridges-after-cleanup.txt"
  ss -ltnp '( sport = :22 or sport = :111 or sport = :8006 or sport = :3128 or sport = :3142 )' > "${VALIDATION_DIR}/host-ports-after-cleanup.txt"
  nft list tables > "${VALIDATION_DIR}/nft-tables-after-cleanup.txt"
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
  local root_dir="${TMP_ROOT}/mnt-${vmid}-rw"
  local loopdev=""

  log "Preparing VM ${vmid} (${GUEST_NAME[${vmid}]}) with offline chroot configuration."
  qm stop "${vmid}" >/dev/null 2>&1 || true
  wait_for_vm_stop "${vmid}"
  qm unlock "${vmid}" >/dev/null 2>&1 || true
  qm config "${vmid}" | grep -q '^net1:' && qm set "${vmid}" -delete net1 >/dev/null 2>&1 || true
  qm config "${vmid}" | grep -q '^ide2:' && qm set "${vmid}" -delete ide2 >/dev/null 2>&1 || true
  qm rollback "${vmid}" post-provision-base
  qm set "${vmid}" --agent 1
  qm set "${vmid}" --net1 "virtio=${VM_TEMP_MAC[${vmid}]},bridge=${HOST_BRIDGE}"

  loopdev="$(mount_vm_rw "${vmid}" "${root_dir}")"
  if ! configure_vm_offline "${vmid}" "${root_dir}"; then
    cleanup_mount_tree "${root_dir}" "${loopdev}"
    loopdev=""
    fail "Offline configuration failed for VM ${vmid}."
  fi
  cleanup_mount_tree "${root_dir}" "${loopdev}"
  loopdev=""

  log "Booting VM ${vmid} for vmbr90 validation."
  qm start "${vmid}"
  wait_for_vm_stop "${vmid}"
  extract_results "${vmid}"
  qm set "${vmid}" -delete net1
}

main() {
  mkdir -p "${TMP_ROOT}" "${VALIDATION_DIR}" "${MANIFEST_DIR}" "${PORTCHECK_DIR}"
  ensure_host_temp_path

  for vmid in ${VM_IDS}; do
    process_vm "${vmid}"
  done

  cleanup_host_temp_path
  create_final_validation
  log "VM chroot fallback completed successfully."
}

main "$@"
