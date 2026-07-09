#!/bin/bash
set -Eeuo pipefail

IAC_ROOT="/root/ailab2-iac"
SECTION_ROOT="${IAC_ROOT}/section-04-network-tor"
BACKUP_DIR="${SECTION_ROOT}/backups"
LOG_DIR="${SECTION_ROOT}/logs"
SCRIPT_DIR="${SECTION_ROOT}/scripts"
VALIDATION_DIR="${SECTION_ROOT}/validation"
PORTCHECK_DIR="${SECTION_ROOT}/port-checks"
TMP_ROOT="/root/ailab2-section4"
ROLLBACK_PID_FILE="${VALIDATION_DIR}/rollback-guard.pid"
HOST_INTERFACES="/etc/network/interfaces"
HOST_NFTABLES="/etc/nftables.conf"
HOST_SYSCTL="/etc/sysctl.d/99-ailab-routing.conf"
NFT_TABLE="ailab"
NFTABLES_ENABLED_BEFORE="disabled"
ROLLBACK_TIMEOUT_SECONDS="1200"
TOR_CTID="101"
TOR_ADMIN_IP="10.10.10.10"
OPERATOR_SOURCE_IP="10.0.2.2"
HOST_VMbr0_IP="10.0.2.15"

declare -A BRIDGE_ADDR=(
  [vmbr10]="10.10.10.1/24"
  [vmbr20]="10.20.20.1/24"
  [vmbr30]="10.30.30.1/24"
  [vmbr40]="10.40.40.1/24"
  [vmbr50]="10.50.50.1/24"
)

declare -A CT_NET0=(
  [101]="name=eth0,bridge=vmbr0,hwaddr=BC:24:11:12:4F:81,gw=10.0.2.2,ip=10.0.2.101/24,type=veth"
  [102]="name=eth0,bridge=vmbr10,hwaddr=BC:24:11:39:E1:4E,ip=10.10.10.20/24,type=veth"
  [103]="name=eth0,bridge=vmbr30,hwaddr=BC:24:11:95:B1:F4,gw=10.30.30.1,ip=10.30.30.103/24,type=veth"
  [104]="name=eth0,bridge=vmbr40,hwaddr=BC:24:11:A0:97:00,gw=10.40.40.1,ip=10.40.40.104/24,type=veth"
)

declare -A CT_NET1=(
  [101]="name=eth1,bridge=vmbr10,hwaddr=BC:24:11:22:93:2A,ip=10.10.10.10/24,type=veth"
  [102]="name=eth1,bridge=vmbr20,hwaddr=BC:24:11:E9:CE:12,ip=10.20.20.20/24,type=veth"
)

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
  local attempts=0

  while true; do
    local state
    state="$(qm status "${vmid}" | awk '{print $2}')"
    [[ "${state}" == "${target}" ]] && return 0
    attempts=$((attempts + 1))
    [[ "${attempts}" -gt 180 ]] && fail "VM ${vmid} did not reach ${target}."
    sleep 2
  done
}

write_section_readmes() {
  mkdir -p "${BACKUP_DIR}" "${LOG_DIR}" "${SCRIPT_DIR}" "${VALIDATION_DIR}" "${PORTCHECK_DIR}" "${TMP_ROOT}"

  cat > "${SECTION_ROOT}/README.md" <<'EOF'
# Section 04 - Network and Tor

Scope of this section:
- static zone addressing for host and guests
- host-side nftables deny-by-default policy
- operator-only management access on vmbr0
- Tor-based admin SSH onion on ct-tor-gateway

Out of scope:
- general user-facing service onions
- app-specific reverse proxy publication
- monitoring or backup services
- real Bitcoin secrets
EOF
}

backup_host_state() {
  cp -a "${HOST_INTERFACES}" "${BACKUP_DIR}/interfaces.pre-section4"
  cp -a "${HOST_NFTABLES}" "${BACKUP_DIR}/nftables.conf.pre-section4"
  if systemctl is-enabled nftables >/dev/null 2>&1; then
    NFTABLES_ENABLED_BEFORE="enabled"
  else
    NFTABLES_ENABLED_BEFORE="disabled"
  fi
  printf '%s\n' "${NFTABLES_ENABLED_BEFORE}" > "${BACKUP_DIR}/nftables.enabled.pre-section4"
}

write_rollback_script() {
  cat > "${SCRIPT_DIR}/section4_host_rollback.sh" <<EOF
#!/bin/bash
set -euo pipefail

cp -af "${BACKUP_DIR}/interfaces.pre-section4" "${HOST_INTERFACES}"
ifreload -a >/dev/null 2>&1 || true

cp -af "${BACKUP_DIR}/nftables.conf.pre-section4" "${HOST_NFTABLES}"
if [[ -f "${BACKUP_DIR}/nftables.enabled.pre-section4" ]] && grep -qx enabled "${BACKUP_DIR}/nftables.enabled.pre-section4"; then
  systemctl enable --now nftables >/dev/null 2>&1 || true
  nft -f "${HOST_NFTABLES}" >/dev/null 2>&1 || true
else
  systemctl stop nftables >/dev/null 2>&1 || true
  systemctl disable nftables >/dev/null 2>&1 || true
  nft flush ruleset >/dev/null 2>&1 || true
fi

rm -f "${HOST_SYSCTL}" >/dev/null 2>&1 || true
sysctl -qw net.ipv4.ip_forward=0 >/dev/null 2>&1 || true
EOF
  chmod 0700 "${SCRIPT_DIR}/section4_host_rollback.sh"
}

start_rollback_guard() {
  nohup bash -lc "sleep ${ROLLBACK_TIMEOUT_SECONDS}; ${SCRIPT_DIR}/section4_host_rollback.sh >/dev/null 2>&1" \
    >/dev/null 2>&1 &
  printf '%s\n' "$!" > "${ROLLBACK_PID_FILE}"
}

cancel_rollback_guard() {
  if [[ -f "${ROLLBACK_PID_FILE}" ]]; then
    kill "$(cat "${ROLLBACK_PID_FILE}")" >/dev/null 2>&1 || true
    rm -f "${ROLLBACK_PID_FILE}"
  fi
}

write_host_interfaces() {
  cat > "${HOST_INTERFACES}" <<'EOF'
auto lo
iface lo inet loopback

iface nic0 inet manual

auto vmbr0
iface vmbr0 inet static
        address 10.0.2.15/24
        gateway 10.0.2.2
        bridge-ports nic0
        bridge-stp off
        bridge-fd 0

iface nic1 inet manual

auto vmbr10
iface vmbr10 inet static
        address 10.10.10.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0

auto vmbr20
iface vmbr20 inet static
        address 10.20.20.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0

auto vmbr30
iface vmbr30 inet static
        address 10.30.30.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0

auto vmbr40
iface vmbr40 inet static
        address 10.40.40.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0

auto vmbr50
iface vmbr50 inet static
        address 10.50.50.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0

source /etc/network/interfaces.d/*
EOF

  cat > "${HOST_SYSCTL}" <<'EOF'
net.ipv4.ip_forward = 1
EOF

  sysctl --system >/dev/null
  ifreload -a
}

write_host_nftables() {
  cat > "${HOST_NFTABLES}" <<EOF
#!/usr/sbin/nft -f

flush ruleset

table inet ${NFT_TABLE} {
  set operator_v4 {
    type ipv4_addr
    elements = { ${OPERATOR_SOURCE_IP} }
  }

  chain input {
    type filter hook input priority filter; policy drop;

    iifname "lo" accept
    ct state established,related accept
    ct state invalid drop

    iifname "vmbr0" ip saddr @operator_v4 tcp dport { 22, 8006 } accept
    iifname "vmbr10" ip saddr ${TOR_ADMIN_IP} tcp dport 22 accept

    reject with icmpx type admin-prohibited
  }

  chain forward {
    type filter hook forward priority filter; policy drop;

    ct state established,related accept

    reject with icmpx type admin-prohibited
  }

  chain output {
    type filter hook output priority filter; policy accept;
  }
}
EOF

  systemctl enable --now nftables >/dev/null
  nft -f "${HOST_NFTABLES}"
}

record_host_validation() {
  ip -4 addr show > "${VALIDATION_DIR}/host-ipv4-addrs.txt"
  ip route show > "${VALIDATION_DIR}/host-routes.txt"
  ss -ltnp '( sport = :22 or sport = :111 or sport = :8006 or sport = :3128 )' > "${VALIDATION_DIR}/host-ports-after-firewall.txt"
  nft list ruleset > "${VALIDATION_DIR}/host-nft-ruleset.txt"
  ss -tnp state established '( sport = :22 )' > "${VALIDATION_DIR}/host-established-ssh.txt" || true
}

configure_ct_network() {
  log "Configuring LXC network definitions."
  pct set 101 -net0 "${CT_NET0[101]}" -net1 "${CT_NET1[101]}" --nameserver 10.0.2.3
  pct set 102 -net0 "${CT_NET0[102]}" -net1 "${CT_NET1[102]}"
  pct set 103 -net0 "${CT_NET0[103]}"
  pct set 104 -net0 "${CT_NET0[104]}"
}

configure_tor_gateway() {
  local tor_script="${TMP_ROOT}/ct101-tor-setup.sh"
  log "Updating ct-tor-gateway and installing Tor admin onion."

  pct start "${TOR_CTID}" >/dev/null
  wait_for_ct_state "${TOR_CTID}" running

  cat > "${tor_script}" <<'EOF'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y --with-new-pkgs upgrade
apt-get install -y tor netcat-openbsd

install -d -m 0755 /var/log/ailab /etc/ailab

if ! grep -q 'BEGIN AILAB ADMIN ONION' /etc/tor/torrc; then
  cat >> /etc/tor/torrc <<'EOT'
# BEGIN AILAB ADMIN ONION
HiddenServiceDir /var/lib/tor/ssh-admin-onion
HiddenServiceVersion 3
HiddenServicePort 22 10.10.10.1:22
# END AILAB ADMIN ONION
EOT
fi

rm -rf /var/lib/tor/ssh-admin-onion
install -d -o debian-tor -g debian-tor -m 0700 /var/lib/tor/ssh-admin-onion

if systemctl list-unit-files | grep -q '^tor@default.service'; then
  systemctl restart tor@default.service
  TOR_UNIT="tor@default.service"
else
  systemctl restart tor.service
  TOR_UNIT="tor.service"
fi

for _ in $(seq 1 150); do
  ip -4 addr show dev eth0 | grep -q '10\.0\.2\.101/24' && \
  ip -4 addr show dev eth1 | grep -q '10\.10\.10\.10/24' && \
  [ -f /var/lib/tor/ssh-admin-onion/hostname ] && \
  journalctl -u "${TOR_UNIT}" --no-pager -n 200 | grep -q 'Bootstrapped 100%' && break
  sleep 2
done

ip -4 addr show dev eth0 | grep -q '10\.0\.2\.101/24'
ip -4 addr show dev eth1 | grep -q '10\.10\.10\.10/24'
[ -f /var/lib/tor/ssh-admin-onion/hostname ]
journalctl -u "${TOR_UNIT}" --no-pager -n 200 | grep -q 'Bootstrapped 100%'

onion="$(cat /var/lib/tor/ssh-admin-onion/hostname)"

check_port() {
  local host="$1"
  local port="$2"
  if timeout 3 bash -lc ": </dev/tcp/${host}/${port}" >/dev/null 2>&1; then
    printf 'open\n'
  else
    printf 'blocked\n'
  fi
}

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
EOF

  pct push "${TOR_CTID}" "${tor_script}" /root/ct101-tor-setup.sh --perms 0755
  pct exec "${TOR_CTID}" -- bash -lc /root/ct101-tor-setup.sh
  pct pull "${TOR_CTID}" /var/log/ailab/section-04-tor-admin-checks.log "${PORTCHECK_DIR}/101-ct-tor-gateway-admin.txt"
  pct pull "${TOR_CTID}" /var/lib/tor/ssh-admin-onion/hostname "${VALIDATION_DIR}/101-admin-ssh-onion.txt"
  pct exec "${TOR_CTID}" -- ip -4 addr show > "${VALIDATION_DIR}/101-ipv4.txt"
  pct exec "${TOR_CTID}" -- ip route show > "${VALIDATION_DIR}/101-routes.txt"
  pct exec "${TOR_CTID}" -- bash -lc 'systemctl status tor.service --no-pager -l || systemctl status tor@default.service --no-pager -l' > "${VALIDATION_DIR}/101-tor-service.txt"
}

validate_ct_ports() {
  local ctid="$1"
  local script_target="$2"
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
echo target=${script_target}
for port in 22 111 8006 3128; do
  echo tcp/${script_target}:\${port}=\$(check_port ${script_target} \${port})
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

  mkdir -p "${root_dir}"
  loopdev="$(losetup --find --show -P "/dev/pve/vm-${vmid}-disk-0")"
  mount "${loopdev}p1" "${root_dir}"
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
  cp "${root_dir}/var/log/ailab/section-04-host-port-checks.log" \
    "${PORTCHECK_DIR}/${vmid}-${VM_NAME[${vmid}]}-host-ports.txt"
  cp "${root_dir}/var/lib/ailab/section-04-network-validated.done" \
    "${VALIDATION_DIR}/${vmid}-section4-done.txt"
  cleanup_vm_mount "${root_dir}" "${loopdev}"
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

    loopdev="$(mount_vm_rw "${vmid}" "${root_dir}")"
    write_vm_network_and_validator "${vmid}" "${root_dir}"
    cleanup_vm_mount "${root_dir}" "${loopdev}"

    log "Booting VM ${vmid} for section 04 validation."
    qm start "${vmid}" >/dev/null
    wait_for_vm_state "${vmid}" stopped
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

main() {
  write_section_readmes
  backup_host_state
  write_rollback_script
  start_rollback_guard

  log "Applying host bridge addressing and routing."
  write_host_interfaces

  log "Applying host nftables deny-by-default policy."
  write_host_nftables
  record_host_validation

  log "Configuring guest network definitions."
  configure_ct_network

  configure_tor_gateway
  validate_ct_ports 102 10.10.10.1
  validate_ct_ports 103 10.30.30.1
  validate_ct_ports 104 10.40.40.1

  configure_vm_networks

  pct shutdown 101 --timeout 60 >/dev/null 2>&1 || pct stop 101 >/dev/null 2>&1 || true
  wait_for_ct_state 101 stopped

  snapshot_all_guests

  pct start 101 >/dev/null
  wait_for_ct_state 101 running
  pct exec 101 -- ip -4 addr show > "${VALIDATION_DIR}/101-ipv4-final.txt"
  pct exec 101 -- ip route show > "${VALIDATION_DIR}/101-routes-final.txt"

  record_final_state
  cancel_rollback_guard
  log "Section 04 network and Tor completed successfully."
}

main "$@"
