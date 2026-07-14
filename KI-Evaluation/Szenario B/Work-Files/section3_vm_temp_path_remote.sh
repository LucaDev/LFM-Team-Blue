#!/bin/bash
set -Eeuo pipefail

HOST_BRIDGE="vmbr90"
HOST_IP="172.31.90.1"
HOST_CIDR="172.31.90.1/24"
PROXY_PORT="3142"
NFT_TABLE="ailab_vmbr90"
TMP_ROOT="/root/ailab2-vm-retry"
SECTION_ROOT="/root/ailab2-iac/section-03-config"
VALIDATION_DIR="${SECTION_ROOT}/validation"

POLICY_CREATED=0
POLICY_BACKUP=""
ACNG_PREINSTALLED=0
ACNG_CONFIG_BACKUP=""

cleanup_policy_rcd() {
  if [[ -n "${POLICY_BACKUP}" && -f "${POLICY_BACKUP}" ]]; then
    mv -f "${POLICY_BACKUP}" /usr/sbin/policy-rc.d
  elif [[ "${POLICY_CREATED}" -eq 1 ]]; then
    rm -f /usr/sbin/policy-rc.d
  fi
}

mkdir -p "${TMP_ROOT}" "${VALIDATION_DIR}"

if ! ip link show "${HOST_BRIDGE}" >/dev/null 2>&1; then
  ip link add name "${HOST_BRIDGE}" type bridge
  ip addr add "${HOST_CIDR}" dev "${HOST_BRIDGE}"
  sysctl -qw "net.ipv6.conf.${HOST_BRIDGE}.disable_ipv6=1" || true
  ip link set "${HOST_BRIDGE}" up
fi
ip -4 addr show "${HOST_BRIDGE}" > "${VALIDATION_DIR}/vmbr90-ip.txt"

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
  host_apt_parts="${TMP_ROOT}/host-apt-sourceparts"
  mkdir -p "${host_apt_parts}"
  cp -a /etc/apt/sources.list.d/debian.sources "${host_apt_parts}/debian.sources"
  apt-get \
    -o "Dir::Etc::sourcelist=/dev/null" \
    -o "Dir::Etc::sourceparts=${host_apt_parts}" \
    -o "APT::Get::List-Cleanup=0" \
    update
  DEBIAN_FRONTEND=noninteractive apt-get \
    -o "Dir::Etc::sourcelist=/dev/null" \
    -o "Dir::Etc::sourceparts=${host_apt_parts}" \
    -o "APT::Get::List-Cleanup=0" \
    install -y apt-cacher-ng
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
ss -ltnp '( sport = :22 or sport = :111 or sport = :8006 or sport = :3128 or sport = :3142 )' > "${VALIDATION_DIR}/apt-proxy-listener.txt"

if nft list table inet "${NFT_TABLE}" >/dev/null 2>&1; then
  nft delete table inet "${NFT_TABLE}"
fi
nft add table inet "${NFT_TABLE}"
nft "add chain inet ${NFT_TABLE} input { type filter hook input priority -150; policy accept; }"
nft "add chain inet ${NFT_TABLE} forward { type filter hook forward priority -150; policy accept; }"
nft add rule inet "${NFT_TABLE}" input iifname "${HOST_BRIDGE}" ip daddr "${HOST_IP}" tcp dport "${PROXY_PORT}" counter accept
nft add rule inet "${NFT_TABLE}" input iifname "${HOST_BRIDGE}" counter drop
nft add rule inet "${NFT_TABLE}" forward iifname "${HOST_BRIDGE}" counter drop
nft list table inet "${NFT_TABLE}" > "${VALIDATION_DIR}/${NFT_TABLE}.txt"

echo "vmbr90-ready"
