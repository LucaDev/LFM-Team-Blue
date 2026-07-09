#!/bin/bash
set -Eeuo pipefail

IAC_ROOT="/root/ailab2-iac"
SECTION_ROOT="${IAC_ROOT}/section-04-network-tor"
VALIDATION_DIR="${SECTION_ROOT}/validation"
PORTCHECK_DIR="${SECTION_ROOT}/port-checks"
TMP_ROOT="/root/ailab2-section4-finalize"
ROLLBACK_PID_FILE="${VALIDATION_DIR}/rollback-guard.pid"

declare -A CT_NAME=(
  [101]="ct-tor-gateway"
  [102]="ct-edge-proxy"
  [103]="ct-monitoring"
  [104]="ct-backup"
)

declare -A VM_NAME=(
  [201]="vm-apps-core"
  [202]="vm-apps-extended"
  [203]="vm-bitcoin-node"
  [204]="vm-bitcoin-service"
)

declare -A VM_MAC=(
  [201]="BC:24:11:44:04:67"
  [202]="BC:24:11:D9:CD:F5"
  [203]="BC:24:11:49:90:46"
  [204]="BC:24:11:C3:9D:62"
)

declare -A VM_ADDR=(
  [201]="10.20.20.201/24"
  [202]="10.20.20.202/24"
  [203]="10.50.50.203/24"
  [204]="10.50.50.204/24"
)

declare -A VM_GATEWAY=(
  [201]="10.20.20.1"
  [202]="10.20.20.1"
  [203]="10.50.50.1"
  [204]="10.50.50.1"
)

declare -A VM_ZONE=(
  [201]="anwendungsdienste"
  [202]="anwendungsdienste"
  [203]="bitcoin-simulation"
  [204]="bitcoin-simulation"
)

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

wait_for_ct_state() {
  local ctid="$1"
  local target="$2"
  local attempts=0
  while true; do
    local state
    state="$(pct status "${ctid}" | awk '{print $2}')"
    [[ "${state}" == "${target}" ]] && return 0
    attempts=$((attempts + 1))
    [[ "${attempts}" -gt 120 ]] && fail "CT ${ctid} did not reach ${target}."
    sleep 2
  done
}

wait_for_vm_state() {
  local vmid="$1"
  local target="$2"
  local max_attempts="${3:-180}"
  local attempts=0
  while true; do
    local state
    state="$(qm status "${vmid}" | awk '{print $2}')"
    [[ "${state}" == "${target}" ]] && return 0
    attempts=$((attempts + 1))
    [[ "${attempts}" -gt "${max_attempts}" ]] && fail "VM ${vmid} did not reach ${target}."
    sleep 2
  done
}

wait_for_vm_validation_window() {
  local vmid="$1"
  local attempts=0
  while true; do
    local state
    state="$(qm status "${vmid}" | awk '{print $2}')"
    [[ "${state}" == "stopped" ]] && return 0
    attempts=$((attempts + 1))
    if [[ "${attempts}" -gt 150 ]]; then
      log "VM ${vmid} still running after validator window; forcing stop for artifact extraction."
      qm stop "${vmid}" >/dev/null 2>&1 || true
      wait_for_vm_state "${vmid}" stopped 60
      return 0
    fi
    sleep 2
  done
}

capture_101_admin_validation() {
  log "Capturing ct-tor-gateway validation."
  pct exec 101 -- bash -lc '
for _ in $(seq 1 60); do
  [ -f /var/lib/tor/ssh-admin-onion/hostname ] && \
  journalctl -u tor@default.service --no-pager -n 120 2>/dev/null | grep -q "Bootstrapped 100%" && break
  sleep 2
done

check_port() {
  local host="$1"
  local port="$2"
  if timeout 3 bash -lc ": </dev/tcp/${host}/${port}" >/dev/null 2>&1; then
    printf "open\n"
  else
    printf "blocked\n"
  fi
}

onion="$(cat /var/lib/tor/ssh-admin-onion/hostname)"
{
  echo "guest=ct-tor-gateway"
  echo "onion=${onion}"
  echo "backend=10.10.10.1:22"
  echo "tcp/10.10.10.1:22=$(check_port 10.10.10.1 22)"
  echo "tcp/10.10.10.1:111=$(check_port 10.10.10.1 111)"
  echo "tcp/10.10.10.1:8006=$(check_port 10.10.10.1 8006)"
  echo "tcp/10.10.10.1:3128=$(check_port 10.10.10.1 3128)"
  echo "tcp/10.0.2.15:22=$(check_port 10.0.2.15 22)"
  echo "tcp/10.0.2.15:111=$(check_port 10.0.2.15 111)"
  echo "tcp/10.0.2.15:8006=$(check_port 10.0.2.15 8006)"
  echo "tcp/10.0.2.15:3128=$(check_port 10.0.2.15 3128)"
  if nc -vz -w 20 -X 5 -x 127.0.0.1:9050 "${onion}" 22 >/dev/null 2>&1; then
    echo "onion/tcp22=open"
  else
    echo "onion/tcp22=blocked"
  fi
} > /var/log/ailab/section-04-tor-admin-checks.log
' 

  pct pull 101 /var/log/ailab/section-04-tor-admin-checks.log "${PORTCHECK_DIR}/101-ct-tor-gateway-admin.txt"
  pct pull 101 /var/lib/tor/ssh-admin-onion/hostname "${VALIDATION_DIR}/101-admin-ssh-onion.txt"
  pct exec 101 -- ip -4 addr show > "${VALIDATION_DIR}/101-ipv4-final.txt"
  pct exec 101 -- ip route show > "${VALIDATION_DIR}/101-routes-final.txt"
  pct exec 101 -- bash -lc 'systemctl status tor@default.service --no-pager -l || systemctl status tor.service --no-pager -l' > "${VALIDATION_DIR}/101-tor-service.txt"
}

validate_ct_ports() {
  local ctid="$1"
  local target="$2"
  local outfile="${PORTCHECK_DIR}/${ctid}-${CT_NAME[${ctid}]}-host-ports.txt"

  pct start "${ctid}" >/dev/null 2>&1 || true
  wait_for_ct_state "${ctid}" running

  pct exec "${ctid}" -- bash -lc "
check_port() {
  local host=\"\$1\"
  local port=\"\$2\"
  if timeout 3 bash -lc \": </dev/tcp/\${host}/\${port}\" >/dev/null 2>&1; then
    printf 'open\n'
  else
    printf 'blocked\n'
  fi
}

echo guest=${CT_NAME[${ctid}]}
echo target=${target}
for port in 22 111 8006 3128; do
  echo tcp/${target}:\${port}=\$(check_port ${target} \${port})
done
" > "${outfile}"

  pct exec "${ctid}" -- ip -4 addr show > "${VALIDATION_DIR}/${ctid}-ipv4.txt"
  pct exec "${ctid}" -- ip route show > "${VALIDATION_DIR}/${ctid}-routes.txt"
  pct shutdown "${ctid}" --timeout 60 >/dev/null 2>&1 || pct stop "${ctid}" >/dev/null 2>&1 || true
  wait_for_ct_state "${ctid}" stopped
}

mount_vm_rw() {
  local vmid="$1"
  local root_dir="$2"
  local loopdev
  local mountdev
  mkdir -p "${root_dir}"
  loopdev="$(losetup --find --show -P "/dev/pve/vm-${vmid}-disk-0")"
  mountdev="$(resolve_vm_mount_device "${loopdev}")"
  mount "${mountdev}" "${root_dir}"
  printf '%s\n' "${loopdev}"
}

mount_vm_ro() {
  local vmid="$1"
  local root_dir="$2"
  local loopdev
  local mountdev
  mkdir -p "${root_dir}"
  loopdev="$(losetup --find --show -P "/dev/pve/vm-${vmid}-disk-0")"
  mountdev="$(resolve_vm_mount_device "${loopdev}")"
  mount -o ro "${mountdev}" "${root_dir}"
  printf '%s\n' "${loopdev}"
}

resolve_vm_mount_device() {
  local loopdev="$1"
  local attempts=0
  while true; do
    if [[ -b "${loopdev}p1" ]]; then
      printf '%s\n' "${loopdev}p1"
      return 0
    fi
    attempts=$((attempts + 1))
    [[ "${attempts}" -gt 20 ]] && fail "Partition device ${loopdev}p1 did not become ready."
    partprobe "${loopdev}" >/dev/null 2>&1 || true
    udevadm settle >/dev/null 2>&1 || true
    sleep 1
  done
}

cleanup_vm_mount() {
  local root_dir="$1"
  local loopdev="$2"
  mountpoint -q "${root_dir}" && umount "${root_dir}"
  [[ -n "${loopdev}" ]] && losetup -d "${loopdev}" >/dev/null 2>&1 || true
  rm -rf "${root_dir}"
}

write_vm_network_and_validator() {
  local vmid="$1"
  local root_dir="$2"
  local name="${VM_NAME[${vmid}]}"
  local zone="${VM_ZONE[${vmid}]}"
  local addr="${VM_ADDR[${vmid}]}"
  local gateway="${VM_GATEWAY[${vmid}]}"
  local mac="${VM_MAC[${vmid}]}"

  rm -f "${root_dir}/etc/systemd/network/10-ailab-net1.network"
  rm -f \
    "${root_dir}/usr/local/sbin/ailab-vmbr90-validate.sh" \
    "${root_dir}/etc/systemd/system/ailab-vmbr90-validate.service" \
    "${root_dir}/etc/systemd/system/multi-user.target.wants/ailab-vmbr90-validate.service" \
    "${root_dir}/var/log/ailab/section-04-host-port-checks.log" \
    "${root_dir}/var/lib/ailab/section-04-network-validated.done"
  mkdir -p \
    "${root_dir}/etc/systemd/system/multi-user.target.wants" \
    "${root_dir}/usr/local/sbin" \
    "${root_dir}/var/lib/ailab" \
    "${root_dir}/var/log/ailab"

  cat > "${root_dir}/etc/systemd/network/10-ailab-net0.network" <<EOF
[Match]
MACAddress=${mac}

[Network]
DHCP=no
Address=${addr}
Gateway=${gateway}
LinkLocalAddressing=no
IPv6AcceptRA=no
EOF

  cat > "${root_dir}/usr/local/sbin/ailab-network-tor-validate.sh" <<EOF
#!/bin/bash
set -euo pipefail

for _ in \$(seq 1 120); do
  if ip -4 addr show | grep -q '${addr}'; then
    break
  fi
  sleep 2
done

ip -4 addr show | grep -q '${addr}'

check_port() {
  local host="\$1"
  local port="\$2"
  if timeout 3 bash -lc ": </dev/tcp/\${host}/\${port}" >/dev/null 2>&1; then
    printf 'open\n'
  else
    printf 'blocked\n'
  fi
}

install -d -m 0755 /var/log/ailab /var/lib/ailab
{
  echo "guest=${name}"
  echo "zone=${zone}"
  echo "gateway=${gateway}"
  for port in 22 111 8006 3128; do
    echo "tcp/${gateway}:\${port}=\$(check_port ${gateway} \${port})"
  done
} > /var/log/ailab/section-04-host-port-checks.log

touch /var/lib/ailab/section-04-network-validated.done
systemctl poweroff --no-wall || poweroff -f
EOF
  chmod 0755 "${root_dir}/usr/local/sbin/ailab-network-tor-validate.sh"

  cat > "${root_dir}/etc/systemd/system/ailab-network-tor-validate.service" <<'EOF'
[Unit]
Description=Ailab section 04 network validator
ConditionPathExists=!/var/lib/ailab/section-04-network-validated.done
Wants=network-online.target systemd-networkd-wait-online.service
After=systemd-networkd.service systemd-networkd-wait-online.service network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ailab-network-tor-validate.sh
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

  ln -sf /etc/systemd/system/ailab-network-tor-validate.service \
    "${root_dir}/etc/systemd/system/multi-user.target.wants/ailab-network-tor-validate.service"
}

extract_vm_validation() {
  local vmid="$1"
  local root_dir="${TMP_ROOT}/mnt-${vmid}-ro"
  local loopdev
  loopdev="$(mount_vm_ro "${vmid}" "${root_dir}")"
  [[ -f "${root_dir}/var/log/ailab/section-04-host-port-checks.log" ]] || fail "VM ${vmid} is missing section-04-host-port-checks.log."
  [[ -f "${root_dir}/var/lib/ailab/section-04-network-validated.done" ]] || fail "VM ${vmid} is missing section-04-network-validated.done."
  cp "${root_dir}/var/log/ailab/section-04-host-port-checks.log" "${PORTCHECK_DIR}/${vmid}-${VM_NAME[${vmid}]}-host-ports.txt"
  cp "${root_dir}/var/lib/ailab/section-04-network-validated.done" "${VALIDATION_DIR}/${vmid}-section4-done.txt"
  cleanup_vm_mount "${root_dir}" "${loopdev}"
}

vm_has_section4_validation() {
  local vmid="$1"
  local root_dir="${TMP_ROOT}/probe-${vmid}"
  local loopdev
  local status=1
  loopdev="$(mount_vm_ro "${vmid}" "${root_dir}")"
  if [[ -f "${root_dir}/var/log/ailab/section-04-host-port-checks.log" && -f "${root_dir}/var/lib/ailab/section-04-network-validated.done" ]]; then
    status=0
  fi
  cleanup_vm_mount "${root_dir}" "${loopdev}"
  return "${status}"
}

configure_vm_networks() {
  local vmid
  for vmid in 201 202 203 204; do
    local root_dir="${TMP_ROOT}/mnt-${vmid}-rw"
    local loopdev=""

    log "Preparing VM ${vmid} (${VM_NAME[${vmid}]}) for network validation."
    qm stop "${vmid}" >/dev/null 2>&1 || true
    wait_for_vm_state "${vmid}" stopped
    qm unlock "${vmid}" >/dev/null 2>&1 || true

    if vm_has_section4_validation "${vmid}"; then
      log "VM ${vmid} already has section 04 validation artifacts; extracting without re-boot."
      extract_vm_validation "${vmid}"
      continue
    fi

    loopdev="$(mount_vm_rw "${vmid}" "${root_dir}")"
    write_vm_network_and_validator "${vmid}" "${root_dir}"
    cleanup_vm_mount "${root_dir}" "${loopdev}"

    log "Booting VM ${vmid} for section 04 validation."
    qm start "${vmid}" >/dev/null
    wait_for_vm_validation_window "${vmid}"
    extract_vm_validation "${vmid}"
  done
}

snapshot_all_guests() {
  log "Creating post-network-tor-base snapshots."
  for ctid in 101 102 103 104; do
    pct listsnapshot "${ctid}" | grep -q post-network-tor-base || pct snapshot "${ctid}" post-network-tor-base >/dev/null
  done
  for vmid in 201 202 203 204; do
    qm listsnapshot "${vmid}" | grep -q post-network-tor-base || qm snapshot "${vmid}" post-network-tor-base >/dev/null
  done
}

record_final_state() {
  ip -4 addr show > "${VALIDATION_DIR}/host-ipv4-addrs-final.txt"
  ip route show > "${VALIDATION_DIR}/host-routes-final.txt"
  ss -ltnp '( sport = :22 or sport = :111 or sport = :8006 or sport = :3128 )' > "${VALIDATION_DIR}/host-ports-final.txt"
  nft list ruleset > "${VALIDATION_DIR}/host-nft-ruleset-final.txt"
  pct list > "${VALIDATION_DIR}/pct-list-final.txt"
  qm list > "${VALIDATION_DIR}/qm-list-final.txt"
  pvesm status > "${VALIDATION_DIR}/pvesm-status-final.txt"

  for ctid in 101 102 103 104; do
    pct config "${ctid}" > "${VALIDATION_DIR}/${ctid}-final-config.txt"
    pct listsnapshot "${ctid}" > "${VALIDATION_DIR}/${ctid}-snapshots.txt"
  done
  for vmid in 201 202 203 204; do
    qm config "${vmid}" > "${VALIDATION_DIR}/${vmid}-final-config.txt"
    qm listsnapshot "${vmid}" > "${VALIDATION_DIR}/${vmid}-snapshots.txt"
  done
}

cancel_rollback_guard() {
  if [[ -f "${ROLLBACK_PID_FILE}" ]]; then
    kill "$(cat "${ROLLBACK_PID_FILE}")" >/dev/null 2>&1 || true
    rm -f "${ROLLBACK_PID_FILE}"
  fi
}

main() {
  mkdir -p "${VALIDATION_DIR}" "${PORTCHECK_DIR}" "${TMP_ROOT}"

  capture_101_admin_validation
  validate_ct_ports 102 10.10.10.1
  validate_ct_ports 103 10.30.30.1
  validate_ct_ports 104 10.40.40.1
  configure_vm_networks

  pct shutdown 101 --timeout 60 >/dev/null 2>&1 || pct stop 101 >/dev/null 2>&1 || true
  wait_for_ct_state 101 stopped

  snapshot_all_guests

  pct start 101 >/dev/null
  wait_for_ct_state 101 running
  record_final_state
  cancel_rollback_guard
  log "Section 04 finalize completed successfully."
}

main "$@"
