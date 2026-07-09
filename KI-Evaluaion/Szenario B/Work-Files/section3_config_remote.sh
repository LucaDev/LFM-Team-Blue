#!/bin/bash
set -Eeuo pipefail

HOST_BRIDGE="vmbr90"
HOST_IP="172.31.90.1"
HOST_CIDR="${HOST_IP}/24"
PROXY_PORT="3142"
NFT_TABLE="ailab_vmbr90"
IAC_ROOT="/root/ailab2-iac"
SECTION_ROOT="${IAC_ROOT}/section-03-config"
TMP_ROOT="/root/ailab2-tmp-config"
ISO_DIR="/var/lib/vz/template/iso"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

RUN_LOG=""
POLICY_BACKUP=""
POLICY_CREATED=0
ACNG_PREINSTALLED=0
ACNG_CONFIG_BACKUP=""
VMBR_CREATED=0
NFT_CREATED=0
PROXY_STARTED=0

declare -a TEMP_ISOS=()

declare -A GUEST_NAME=(
  [101]="ct-tor-gateway"
  [102]="ct-edge-proxy"
  [103]="ct-monitoring"
  [104]="ct-backup"
  [201]="vm-apps-core"
  [202]="vm-apps-extended"
  [203]="vm-bitcoin-node"
  [204]="vm-bitcoin-service"
)

declare -A GUEST_FQDN=(
  [102]="ct-edge-proxy.infra.ailab.internal"
  [103]="ct-monitoring.monitoring.ailab.internal"
  [104]="ct-backup.backup.ailab.internal"
  [201]="vm-apps-core.apps.ailab.internal"
  [202]="vm-apps-extended.apps.ailab.internal"
  [203]="vm-bitcoin-node.bitcoin.ailab.internal"
  [204]="vm-bitcoin-service.bitcoin.ailab.internal"
)

declare -A GUEST_ZONE=(
  [101]="infrastruktur"
  [102]="infrastruktur"
  [103]="monitoring"
  [104]="backup"
  [201]="anwendungsdienste"
  [202]="anwendungsdienste"
  [203]="bitcoin-simulation"
  [204]="bitcoin-simulation"
)

declare -A GUEST_SRV_PATHS=(
  [102]="/srv/edge-proxy"
  [103]="/srv/monitoring"
  [104]="/srv/backup-staging /srv/restore"
  [201]="/srv/apps-core"
  [202]="/srv/apps-extended"
  [203]="/srv/bitcoin-sim/node"
  [204]="/srv/bitcoin-sim/service"
)

declare -A GUEST_MIN_PACKAGES=(
  [101]=""
  [102]=""
  [103]=""
  [104]=""
  [201]="qemu-guest-agent cloud-guest-utils"
  [202]="qemu-guest-agent cloud-guest-utils"
  [203]="qemu-guest-agent cloud-guest-utils"
  [204]="qemu-guest-agent cloud-guest-utils"
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

declare -A CT_TEMP_IP=(
  [102]="172.31.90.102"
  [103]="172.31.90.103"
  [104]="172.31.90.104"
)

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

setup_logging() {
  mkdir -p "${SECTION_ROOT}/"{logs,manifests,port-checks,scripts,vm-seed,validation}
  mkdir -p "${TMP_ROOT}"
  RUN_LOG="${SECTION_ROOT}/logs/run-${TIMESTAMP}.log"
  exec > >(tee -a "${RUN_LOG}") 2>&1
  log "Section 03 configuration run started."
}

cleanup_policy_rcd() {
  if [[ -n "${POLICY_BACKUP}" && -e "${POLICY_BACKUP}" ]]; then
    mv -f "${POLICY_BACKUP}" /usr/sbin/policy-rc.d
  elif [[ "${POLICY_CREATED}" -eq 1 ]]; then
    rm -f /usr/sbin/policy-rc.d
  fi
}

cleanup_resources() {
  set +e
  log "Cleanup started."

  for ctid in 102 103 104; do
    pct status "${ctid}" 2>/dev/null | grep -q running && pct shutdown "${ctid}" --timeout 60 >/dev/null 2>&1
    pct status "${ctid}" 2>/dev/null | grep -q running && pct stop "${ctid}" >/dev/null 2>&1
    pct config "${ctid}" 2>/dev/null | grep -q '^net9:' && pct set "${ctid}" -delete net9 >/dev/null 2>&1
  done

  for vmid in 201 202 203 204; do
    qm status "${vmid}" 2>/dev/null | grep -q running && qm shutdown "${vmid}" --timeout 120 >/dev/null 2>&1
    qm status "${vmid}" 2>/dev/null | grep -q running && qm stop "${vmid}" >/dev/null 2>&1
    qm config "${vmid}" 2>/dev/null | grep -q '^net1:' && qm set "${vmid}" -delete net1 >/dev/null 2>&1
    qm config "${vmid}" 2>/dev/null | grep -q '^ide2:' && qm set "${vmid}" -delete ide2 >/dev/null 2>&1
  done

  if [[ "${PROXY_STARTED}" -eq 1 ]]; then
    systemctl stop apt-cacher-ng >/dev/null 2>&1
  fi

  if [[ -n "${ACNG_CONFIG_BACKUP}" && -e "${ACNG_CONFIG_BACKUP}" ]]; then
    mv -f "${ACNG_CONFIG_BACKUP}" /etc/apt-cacher-ng/acng.conf
  fi

  if [[ "${ACNG_PREINSTALLED}" -eq 0 ]] && dpkg-query -W -f='${Status}' apt-cacher-ng 2>/dev/null | grep -q 'install ok installed'; then
    DEBIAN_FRONTEND=noninteractive apt-get purge -y apt-cacher-ng >/dev/null 2>&1
    apt-get clean >/dev/null 2>&1
  fi

  cleanup_policy_rcd

  if [[ "${NFT_CREATED}" -eq 1 ]] && nft list table inet "${NFT_TABLE}" >/dev/null 2>&1; then
    nft delete table inet "${NFT_TABLE}" >/dev/null 2>&1
  fi

  if [[ "${VMBR_CREATED}" -eq 1 ]]; then
    ip link show "${HOST_BRIDGE}" >/dev/null 2>&1 && ip link set "${HOST_BRIDGE}" down >/dev/null 2>&1
    ip link show "${HOST_BRIDGE}" >/dev/null 2>&1 && ip link delete "${HOST_BRIDGE}" type bridge >/dev/null 2>&1
  fi

  for iso_path in "${TEMP_ISOS[@]}"; do
    rm -f "${iso_path}"
  done

  rm -rf "${TMP_ROOT}"
  log "Cleanup finished."
}

on_error() {
  local line="$1"
  local code="$2"
  log "Failure at line ${line} with exit code ${code}."
  cleanup_resources
  exit "${code}"
}

trap 'on_error ${LINENO} $?' ERR

precheck_scope() {
  log "Running prechecks."
  hostname | grep -qx "ailab2" || fail "Unexpected host; expected ailab2."
  ip link show "${HOST_BRIDGE}" >/dev/null 2>&1 && fail "${HOST_BRIDGE} already exists."
  nft list table inet "${NFT_TABLE}" >/dev/null 2>&1 && fail "nft table ${NFT_TABLE} already exists."
  pct status 101 | grep -q stopped || fail "101 must remain stopped for this section."
  for ctid in 102 103 104; do
    if pct config "${ctid}" | grep -q '^net9:'; then
      fail "Temporary net9 already present on CT ${ctid}."
    fi
  done
  for vmid in 201 202 203 204; do
    if qm config "${vmid}" | grep -q '^net1:'; then
      fail "Temporary net1 already present on VM ${vmid}."
    fi
    if qm config "${vmid}" | grep -q '^ide2:'; then
      fail "Temporary ide2 already present on VM ${vmid}."
    fi
  done
}

write_iac_readme() {
  mkdir -p "${IAC_ROOT}"
  cat > "${IAC_ROOT}/README.md" <<'EOF'
# ailab2 IaC

This repository contains host-local implementation notes, guest manifests and
section-specific bootstrap artifacts for the isolated `ailab2` Proxmox test VM.

Rules:
- No real secrets belong in this tree.
- Only placeholders, templates, manifests and dummy-only Bitcoin simulation data
  are allowed.
- The host-side helper path for section 03 is temporary by design and must be
  fully removed after validation.
EOF

  cat > "${SECTION_ROOT}/README.md" <<'EOF'
# Section 03 - Configuration Baseline

Scope of this section:
- guest-internal configuration baseline for 102, 103, 104, 201, 202, 203 and 204
- 101 stays stopped and unchanged
- temporary package supply via `vmbr90` and a host-local APT proxy only
- real package updates are applied with `apt-get update` plus
  `apt-get --with-new-pkgs upgrade`

Out of scope:
- app runtimes such as Docker, Podman, databases or webservers
- Tor publication
- app-specific firewall rules
- real Bitcoin secrets or productive API credentials

No-Secrets rule:
- no real `.env` values
- no productive private keys
- no productive wallet data
- no seeds, `xprv` or productive signing material
EOF

  cat > "${SECTION_ROOT}/guest-baseline.tsv" <<'EOF'
id	name	zone	minimal-packages	config-goals
101	ct-tor-gateway	infrastruktur	none	no live changes in section 03; host-side metadata only
102	ct-edge-proxy	infrastruktur	none	apt baseline, timezone, journald limits, /etc/ailab, /srv/edge-proxy
103	ct-monitoring	monitoring	none	apt baseline, timezone, journald limits, /etc/ailab, /srv/monitoring
104	ct-backup	backup	none	apt baseline, timezone, journald limits, /etc/ailab, /srv/backup-staging, /srv/restore
201	vm-apps-core	anwendungsdienste	qemu-guest-agent cloud-guest-utils	apt baseline, guest-agent, disk growth, journald limits, /etc/ailab, /srv/apps-core
202	vm-apps-extended	anwendungsdienste	qemu-guest-agent cloud-guest-utils	apt baseline, guest-agent, disk growth, journald limits, /etc/ailab, /srv/apps-extended
203	vm-bitcoin-node	bitcoin-simulation	qemu-guest-agent cloud-guest-utils	apt baseline, guest-agent, disk growth, journald limits, /etc/ailab, /srv/bitcoin-sim/node, dummy-only notice
204	vm-bitcoin-service	bitcoin-simulation	qemu-guest-agent cloud-guest-utils	apt baseline, guest-agent, disk growth, journald limits, /etc/ailab, /srv/bitcoin-sim/service, dummy-only notice
EOF
}

setup_vmbr90() {
  log "Creating temporary bridge ${HOST_BRIDGE}."
  ip link add name "${HOST_BRIDGE}" type bridge
  VMBR_CREATED=1
  ip addr add "${HOST_CIDR}" dev "${HOST_BRIDGE}"
  sysctl -qw "net.ipv6.conf.${HOST_BRIDGE}.disable_ipv6=1" || true
  ip link set "${HOST_BRIDGE}" up
  ip -br addr show "${HOST_BRIDGE}" | tee "${SECTION_ROOT}/validation/${HOST_BRIDGE}-ip.txt"
}

setup_host_proxy() {
  log "Installing temporary APT proxy."
  local host_apt_parts="${TMP_ROOT}/host-apt-sourceparts"
  local -a host_apt_args=(
    -o "Dir::Etc::sourcelist=/dev/null"
    -o "Dir::Etc::sourceparts=${host_apt_parts}"
    -o "APT::Get::List-Cleanup=0"
  )

  if [[ -e /usr/sbin/policy-rc.d ]]; then
    POLICY_BACKUP="${TMP_ROOT}/policy-rc.d.orig"
    cp -a /usr/sbin/policy-rc.d "${POLICY_BACKUP}"
  else
    POLICY_CREATED=1
  fi

  cat > /usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
  chmod 0755 /usr/sbin/policy-rc.d

  if dpkg-query -W -f='${Status}' apt-cacher-ng 2>/dev/null | grep -q 'install ok installed'; then
    ACNG_PREINSTALLED=1
  else
    mkdir -p "${host_apt_parts}"
    cp -a /etc/apt/sources.list.d/debian.sources "${host_apt_parts}/debian.sources"
    DEBIAN_FRONTEND=noninteractive apt-get "${host_apt_args[@]}" update
    DEBIAN_FRONTEND=noninteractive apt-get "${host_apt_args[@]}" install -y apt-cacher-ng
  fi

  cleanup_policy_rcd

  ACNG_CONFIG_BACKUP="${TMP_ROOT}/acng.conf.orig"
  cp -a /etc/apt-cacher-ng/acng.conf "${ACNG_CONFIG_BACKUP}"
  python3 - "${HOST_IP}" "${PROXY_PORT}" <<'PY'
from pathlib import Path
import sys

host_ip = sys.argv[1]
proxy_port = sys.argv[2]
path = Path("/etc/apt-cacher-ng/acng.conf")
lines = []
for line in path.read_text().splitlines():
    if line.startswith("BindAddress:") or line.startswith("Port:") or line.startswith("PassThroughPattern:"):
        continue
    lines.append(line)
lines.append(f"BindAddress: {host_ip}")
lines.append(f"Port: {proxy_port}")
lines.append("PassThroughPattern: .*")
path.write_text("\n".join(lines) + "\n")
PY

  systemctl start apt-cacher-ng
  PROXY_STARTED=1
  ss -ltnp | grep -F "${HOST_IP}:${PROXY_PORT}" | tee "${SECTION_ROOT}/validation/apt-proxy-listener.txt"
}

setup_nft_guard() {
  log "Installing temporary nftables guard for ${HOST_BRIDGE}."
  nft add table inet "${NFT_TABLE}"
  NFT_CREATED=1
  nft "add chain inet ${NFT_TABLE} input { type filter hook input priority -150; policy accept; }"
  nft "add chain inet ${NFT_TABLE} forward { type filter hook forward priority -150; policy accept; }"
  nft add rule inet "${NFT_TABLE}" input iifname "${HOST_BRIDGE}" ip daddr "${HOST_IP}" tcp dport "${PROXY_PORT}" counter accept
  nft add rule inet "${NFT_TABLE}" input iifname "${HOST_BRIDGE}" counter drop
  nft add rule inet "${NFT_TABLE}" forward iifname "${HOST_BRIDGE}" counter drop
  nft list table inet "${NFT_TABLE}" | tee "${SECTION_ROOT}/validation/${NFT_TABLE}.txt"
}

ensure_stopped() {
  local kind="$1"
  local id="$2"
  local timeout="$3"
  local state=""
  local attempts=0
  while true; do
    if [[ "${kind}" == "ct" ]]; then
      state="$(pct status "${id}" | awk '{print $2}')"
    else
      state="$(qm status "${id}" | awk '{print $2}')"
    fi
    [[ "${state}" == "stopped" ]] && break
    attempts=$((attempts + 1))
    [[ "${attempts}" -gt "${timeout}" ]] && fail "${kind} ${id} did not reach stopped state."
    sleep 5
  done
}

generate_common_guest_script() {
  local id="$1"
  local name="$2"
  local zone="$3"
  local fqdn="$4"
  local srv_paths="$5"
  local extra_packages="$6"
  local script_path="$7"

  cat > "${script_path}" <<EOF
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

cat > /etc/apt/apt.conf.d/90ailab-provision-proxy <<'EOP'
Acquire::http::Proxy "http://${HOST_IP}:${PROXY_PORT}";
Acquire::https::Proxy "http://${HOST_IP}:${PROXY_PORT}";
EOP

apt-get update
apt-get -y --with-new-pkgs upgrade

if [[ -n "${extra_packages}" ]]; then
  apt-get install -y ${extra_packages}
fi

ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
printf 'Etc/UTC\n' > /etc/timezone

install -d -m 0755 /etc/ailab /var/log/ailab /etc/systemd/journald.conf.d
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
rm -f /etc/apt/apt.conf.d/90ailab-provision-proxy
EOF
}

configure_container() {
  local ctid="$1"
  local name="${GUEST_NAME[${ctid}]}"
  local zone="${GUEST_ZONE[${ctid}]}"
  local fqdn="${GUEST_FQDN[${ctid}]}"
  local srv_paths="${GUEST_SRV_PATHS[${ctid}]}"
  local extra_packages="${GUEST_MIN_PACKAGES[${ctid}]}"
  local script_host="${TMP_ROOT}/${name}-section3.sh"

  log "Configuring CT ${ctid} (${name})."
  generate_common_guest_script "${ctid}" "${name}" "${zone}" "${fqdn}" "${srv_paths}" "${extra_packages}" "${script_host}"
  pct set "${ctid}" -net9 "name=eth9,bridge=${HOST_BRIDGE},ip=manual,type=veth"
  pct start "${ctid}"
  pct exec "${ctid}" -- bash -lc "ip link set eth9 up; ip addr flush dev eth9 || true; ip addr add ${CT_TEMP_IP[${ctid}]}/24 dev eth9; ip route replace ${HOST_IP}/32 dev eth9"
  pct exec "${ctid}" -- ip -br addr show dev eth9 > "${SECTION_ROOT}/validation/${ctid}-${name}-eth9.txt"
  pct exec "${ctid}" -- ip route show > "${SECTION_ROOT}/validation/${ctid}-${name}-routes.txt"
  pct exec "${ctid}" -- bash -lc "timeout 3 bash -lc ': </dev/tcp/${HOST_IP}/${PROXY_PORT}'" >/dev/null
  pct push "${ctid}" "${script_host}" /root/ailab-section3.sh --perms 0755
  pct exec "${ctid}" -- bash -lc /root/ailab-section3.sh
  pct pull "${ctid}" /var/log/ailab/package-manifest.txt "${SECTION_ROOT}/manifests/${ctid}-${name}-package-manifest.txt"
  pct pull "${ctid}" /var/log/ailab/vmbr90-port-checks.log "${SECTION_ROOT}/port-checks/${ctid}-${name}-vmbr90.txt"
  pct exec "${ctid}" -- findmnt -no SOURCE,FSTYPE,SIZE / > "${SECTION_ROOT}/validation/${ctid}-${name}-rootfs.txt"
  pct shutdown "${ctid}" --timeout 60 || pct stop "${ctid}"
  ensure_stopped ct "${ctid}" 24
  pct set "${ctid}" -delete net9
}

vm_capture_to_file() {
  local vmid="$1"
  local command="$2"
  local outfile="$3"
  local raw_json

  raw_json="$(qm guest exec "${vmid}" -- bash -lc "${command}")"
  printf '%s\n' "${raw_json}" | python3 - "${outfile}" <<'PY'
import json
import pathlib
import sys

data = json.load(sys.stdin)
path = pathlib.Path(sys.argv[1])
path.write_text(data.get("out-data", ""))
sys.stderr.write(data.get("err-data", ""))
code = int(data.get("exitcode", 0))
sys.exit(code)
PY
}

wait_for_qga() {
  local vmid="$1"
  local attempts=0
  until qm guest cmd "${vmid}" ping >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    [[ "${attempts}" -gt 120 ]] && fail "QGA did not become ready for VM ${vmid}."
    sleep 5
  done
}

wait_for_vm_file() {
  local vmid="$1"
  local target_file="$2"
  local attempts=0
  until qm guest exec "${vmid}" -- bash -lc "test -f '${target_file}' && echo ready" | grep -q ready; do
    attempts=$((attempts + 1))
    [[ "${attempts}" -gt 120 ]] && fail "VM ${vmid} did not create ${target_file}."
    sleep 5
  done
}

build_vm_seed_iso() {
  local vmid="$1"
  local name="${GUEST_NAME[${vmid}]}"
  local zone="${GUEST_ZONE[${vmid}]}"
  local fqdn="${GUEST_FQDN[${vmid}]}"
  local srv_paths="${GUEST_SRV_PATHS[${vmid}]}"
  local extra_packages="${GUEST_MIN_PACKAGES[${vmid}]}"
  local seed_root="${SECTION_ROOT}/vm-seed/${vmid}-${name}"
  local guest_script="${seed_root}/guest-script.sh"
  local iso_name="ailab-section3-${vmid}.iso"
  local iso_path="${ISO_DIR}/${iso_name}"
  local net0_mac

  net0_mac="$(qm config "${vmid}" | awk -F'[=,]' '/^net0:/{print $2}')"
  [[ -n "${net0_mac}" ]] || fail "Could not determine net0 MAC for VM ${vmid}."

  mkdir -p "${seed_root}"
  generate_common_guest_script "${vmid}" "${name}" "${zone}" "${fqdn}" "${srv_paths}" "${extra_packages}" "${guest_script}"

  cat > "${seed_root}/meta-data" <<EOF
instance-id: ailab-section3-${vmid}-${TIMESTAMP}
local-hostname: ${name}
EOF

  cat > "${seed_root}/network-config" <<EOF
version: 2
ethernets:
  net0:
    match:
      macaddress: "${net0_mac}"
    set-name: eth0
    dhcp4: false
    dhcp6: false
  net1:
    match:
      macaddress: "${VM_TEMP_MAC[${vmid}]}"
    set-name: eth1
    dhcp4: false
    dhcp6: false
    addresses:
      - ${VM_TEMP_IP[${vmid}]}/24
EOF

  {
    echo "#cloud-config"
    echo "preserve_hostname: false"
    echo "hostname: ${name}"
    echo "fqdn: ${fqdn}"
    echo "package_update: false"
    echo "package_upgrade: false"
    echo "write_files:"
    echo "  - path: /usr/local/sbin/ailab-section3.sh"
    echo "    permissions: '0755'"
    echo "    owner: root:root"
    echo "    content: |"
    sed 's/^/      /' "${guest_script}"
    echo "runcmd:"
    echo "  - [ bash, -lc, /usr/local/sbin/ailab-section3.sh ]"
    echo "power_state:"
    echo "  mode: poweroff"
    echo "  timeout: 30"
    echo "  condition: true"
    echo "final_message: ailab section 03 baseline applied"
  } > "${seed_root}/user-data"

  genisoimage -quiet -output "${iso_path}" -volid CIDATA -joliet -rock \
    "${seed_root}/user-data" "${seed_root}/meta-data" "${seed_root}/network-config"
  TEMP_ISOS+=("${iso_path}")
}

configure_vm() {
  local vmid="$1"
  local name="${GUEST_NAME[${vmid}]}"
  local iso_name="ailab-section3-${vmid}.iso"

  log "Configuring VM ${vmid} (${name})."
  build_vm_seed_iso "${vmid}"

  qm set "${vmid}" --agent 1
  qm set "${vmid}" --net1 "virtio=${VM_TEMP_MAC[${vmid}]},bridge=${HOST_BRIDGE}"
  qm set "${vmid}" --ide2 "local:iso/${iso_name},media=cdrom"

  qm start "${vmid}"
  ensure_stopped vm "${vmid}" 240

  qm start "${vmid}"
  wait_for_qga "${vmid}"
  wait_for_vm_file "${vmid}" /var/log/ailab/section-03-config.done

  vm_capture_to_file "${vmid}" "cat /var/log/ailab/package-manifest.txt" "${SECTION_ROOT}/manifests/${vmid}-${name}-package-manifest.txt"
  vm_capture_to_file "${vmid}" "cat /var/log/ailab/vmbr90-port-checks.log" "${SECTION_ROOT}/port-checks/${vmid}-${name}-vmbr90.txt"
  vm_capture_to_file "${vmid}" "findmnt -no SOURCE,FSTYPE,SIZE /" "${SECTION_ROOT}/validation/${vmid}-${name}-rootfs.txt"
  vm_capture_to_file "${vmid}" "for port in ${PROXY_PORT} 22 111 8006 3128; do if timeout 2 bash -lc \": </dev/tcp/${HOST_IP}/\\\$port\" >/dev/null 2>&1; then echo tcp/\\\$port=open; else echo tcp/\\\$port=blocked; fi; done" "${SECTION_ROOT}/port-checks/${vmid}-${name}-vmbr90-live.txt"

  qm shutdown "${vmid}" --timeout 120 || qm stop "${vmid}"
  ensure_stopped vm "${vmid}" 48
  qm set "${vmid}" -delete net1
  qm set "${vmid}" -delete ide2
  rm -f "${ISO_DIR}/${iso_name}"
}

validate_cleanup_state() {
  log "Validating cleanup state."
  ! ip link show "${HOST_BRIDGE}" >/dev/null 2>&1
  ! nft list table inet "${NFT_TABLE}" >/dev/null 2>&1
  ! ss -ltnp | grep -F "${HOST_IP}:${PROXY_PORT}" >/dev/null 2>&1
  for ctid in 102 103 104; do
    pct status "${ctid}" | grep -q stopped
    ! pct config "${ctid}" | grep -q '^net9:'
  done
  pct status 101 | grep -q stopped
  for vmid in 201 202 203 204; do
    qm status "${vmid}" | grep -q stopped
    ! qm config "${vmid}" | grep -q '^net1:'
    ! qm config "${vmid}" | grep -q '^ide2:'
  done
  if dpkg-query -W -f='${Status}' apt-cacher-ng 2>/dev/null | grep -q 'install ok installed'; then
    echo "apt-cacher-ng=installed" > "${SECTION_ROOT}/validation/host-proxy-package-state.txt"
  else
    echo "apt-cacher-ng=absent" > "${SECTION_ROOT}/validation/host-proxy-package-state.txt"
  fi
}

create_post_config_snapshots() {
  log "Creating post-config-base snapshots."
  for ctid in 101 102 103 104; do
    pct snapshot "${ctid}" post-config-base
  done
  for vmid in 201 202 203 204; do
    qm snapshot "${vmid}" post-config-base
  done
}

capture_final_validation() {
  log "Capturing final validation artifacts."
  pct listsnapshot 101 > "${SECTION_ROOT}/validation/101-snapshots.txt"
  for ctid in 102 103 104; do
    pct listsnapshot "${ctid}" > "${SECTION_ROOT}/validation/${ctid}-snapshots.txt"
  done
  for vmid in 201 202 203 204; do
    qm listsnapshot "${vmid}" > "${SECTION_ROOT}/validation/${vmid}-snapshots.txt"
    qm config "${vmid}" > "${SECTION_ROOT}/validation/${vmid}-final-config.txt"
  done
  for ctid in 101 102 103 104; do
    pct config "${ctid}" > "${SECTION_ROOT}/validation/${ctid}-final-config.txt"
  done
  qm list > "${SECTION_ROOT}/validation/qm-list.txt"
  pct list > "${SECTION_ROOT}/validation/pct-list.txt"
  pvesm status > "${SECTION_ROOT}/validation/pvesm-status.txt"
}

main() {
  setup_logging
  write_iac_readme
  precheck_scope
  setup_vmbr90
  setup_host_proxy
  setup_nft_guard

  configure_container 102
  configure_container 103
  configure_container 104

  configure_vm 201
  configure_vm 202
  configure_vm 203
  configure_vm 204

  cleanup_resources
  trap - ERR

  validate_cleanup_state
  create_post_config_snapshots
  capture_final_validation

  log "Section 03 configuration run finished successfully."
}

main "$@"
