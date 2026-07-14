#!/bin/bash
set -Eeuo pipefail

IAC_ROOT="/root/ailab2-iac"
SECTION_ROOT="${IAC_ROOT}/section-06-bitcoin-simulation"
BACKUP_DIR="${SECTION_ROOT}/backups"
LOG_DIR="${SECTION_ROOT}/logs"
SCRIPT_DIR="${SECTION_ROOT}/scripts"
MANIFEST_DIR="${SECTION_ROOT}/manifests"
STAGING_DIR="${SECTION_ROOT}/staging"
VALIDATION_DIR="${SECTION_ROOT}/validation"
TMP_ROOT="/root/ailab2-section06"
RUNTIME_ROOT="/root/ailab-runtime/bitcoin-sim-offline"
NODE_VMID="203"
SERVICE_VMID="204"
NODE_ADDR="10.50.50.203"
SERVICE_ADDR="10.50.50.204"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

wait_for_vm_state() {
  local vmid="$1"
  local target="$2"
  local attempts="${3:-180}"
  local delay="${4:-2}"
  local count=0

  while true; do
    local state
    state="$(qm status "${vmid}" | awk '{print $2}')"
    [[ "${state}" == "${target}" ]] && return 0
    count=$((count + 1))
    [[ "${count}" -ge "${attempts}" ]] && return 1
    sleep "${delay}"
  done
}

ensure_vm_stopped() {
  local vmid="$1"

  qm stop "${vmid}" >/dev/null 2>&1 || true
  if ! wait_for_vm_state "${vmid}" stopped 90 2; then
    qm stop "${vmid}" --skiplock 1 >/dev/null 2>&1 || true
    wait_for_vm_state "${vmid}" stopped 60 2 || fail "VM ${vmid} did not stop."
  fi
  qm unlock "${vmid}" >/dev/null 2>&1 || true
}

cleanup_vm_mount() {
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

mount_vm_rw() {
  local vmid="$1"
  local root_dir="$2"
  local loopdev

  mkdir -p "${root_dir}"
  loopdev="$(losetup --find --show -P "/dev/pve/vm-${vmid}-disk-0")"
  e2fsck -pf "${loopdev}p1" >/dev/null 2>&1 || true
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

write_section_readme() {
  cat > "${SECTION_ROOT}/README.md" <<'EOF'
# Section 06 - Bitcoin Simulation

Scope of this section:
- strict dummy-only Bitcoin role separation on `203` and `204`
- no Bitcoin daemons, no chain sync, no RPC, no onion publication
- file-based watch-only, unsigned PSBT and offline-signing simulation
- validator proof for no Bitcoin listeners, restrictive permissions and end-to-end dummy workflow

Out of scope:
- real seeds, xprv, wallet.dat or productive private keys
- real Bitcoin Core, Electrs, HWI or wallet interoperability
- productive API credentials
- real broadcast or on-chain activity
EOF
}

prepare_host_paths() {
  mkdir -p "${BACKUP_DIR}" "${LOG_DIR}" "${SCRIPT_DIR}" "${MANIFEST_DIR}" "${STAGING_DIR}" "${VALIDATION_DIR}" "${TMP_ROOT}"
  exec > >(tee -a "${LOG_DIR}/section06-apply.log") 2>&1
  write_section_readme

  if [[ -d "${RUNTIME_ROOT}" ]]; then
    [[ "${RUNTIME_ROOT}" == "/root/ailab-runtime/bitcoin-sim-offline" ]] || fail "Unexpected runtime root ${RUNTIME_ROOT}."
    tar -C /root/ailab-runtime -czf "${BACKUP_DIR}/bitcoin-sim-offline.pre-section06.tgz" bitcoin-sim-offline >/dev/null 2>&1 || true
    rm -rf "${RUNTIME_ROOT}"
  fi

  install -d -m 0700 /root/ailab-runtime
  install -d -m 0700 "${RUNTIME_ROOT}"
  install -d -m 0700 "${RUNTIME_ROOT}/watchonly-export" "${RUNTIME_ROOT}/unsigned" "${RUNTIME_ROOT}/signed" "${RUNTIME_ROOT}/receipts" "${RUNTIME_ROOT}/logs"
}

snapshot_guest() {
  local vmid="$1"
  local name="$2"
  local snapshot="$3"

  ensure_vm_stopped "${vmid}"
  if qm listsnapshot "${vmid}" | grep -Eq "(^|[[:space:]])${snapshot}([[:space:]]|$)"; then
    log "Snapshot ${snapshot} already exists for ${name} (${vmid})."
  else
    log "Creating snapshot ${snapshot} for ${name} (${vmid})."
    qm snapshot "${vmid}" "${snapshot}" >/dev/null
  fi
}

prepare_snapshots() {
  snapshot_guest "${NODE_VMID}" "vm-bitcoin-node" "pre-bitcoin-sim"
  snapshot_guest "${SERVICE_VMID}" "vm-bitcoin-service" "pre-bitcoin-sim"
}

relax_boot_efi_fstab() {
  local root_dir="$1"
  local fstab="${root_dir}/etc/fstab"

  [[ -f "${fstab}" ]] || return 0
  if grep -Eq '^[^#[:space:]]+[[:space:]]+/boot/efi[[:space:]]+vfat[[:space:]]+' "${fstab}"; then
    sed -i -E \
      's#^([^#[:space:]]+[[:space:]]+/boot/efi[[:space:]]+vfat[[:space:]]+)([^[:space:]]+)([[:space:]]+[0-9]+[[:space:]]+[0-9]+)$#\1defaults,umask=077,nofail,x-systemd.device-timeout=1s\3#' \
      "${fstab}"
  fi
}

configure_node_offline() {
  local root_dir="$1"

  rm -rf \
    "${root_dir}/var/lib/ailab/bitcoin-sim" \
    "${root_dir}/srv/bitcoin-sim/node/reference" \
    "${root_dir}/srv/bitcoin-sim/node/export" \
    "${root_dir}/srv/bitcoin-sim/node/validation"
  rm -f \
    "${root_dir}/usr/local/sbin/ailab-bitcoin-node-export.sh" \
    "${root_dir}/etc/systemd/system/ailab-bitcoin-node-export.service" \
    "${root_dir}/etc/systemd/system/multi-user.target.wants/ailab-bitcoin-node-export.service" \
    "${root_dir}/var/log/ailab/section-06-node.log" \
    "${root_dir}/var/log/ailab/section-06-package-manifest.txt"

  cat > "${root_dir}/usr/local/sbin/ailab-bitcoin-node-export.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
umask 027

exec >>/var/log/ailab/section-06-node.log 2>&1

STATE_DIR="/var/lib/ailab/bitcoin-sim"
NODE_ROOT="/srv/bitcoin-sim/node"
VALIDATION_DIR="${NODE_ROOT}/validation"

install -d -m 0750 "${STATE_DIR}" "${NODE_ROOT}" "${NODE_ROOT}/reference" "${NODE_ROOT}/export" "${VALIDATION_DIR}" /var/log/ailab
chmod 0750 "${NODE_ROOT}" "${NODE_ROOT}/reference" "${NODE_ROOT}/export" "${VALIDATION_DIR}" "${STATE_DIR}"

cat > "${NODE_ROOT}/reference/descriptor-template.json" <<'EOD'
{
  "artifact_class": "dummy-watch-only-descriptor",
  "descriptor_template": "DUMMY_DESCRIPTOR_TEMPLATE_ONLY",
  "signing_material": "absent",
  "allowed_use": [
    "watch-only-analysis",
    "unsigned-psbt-preparation"
  ],
  "forbidden_use": [
    "real-funds",
    "seed-import",
    "private-key-storage"
  ]
}
EOD

cat > "${NODE_ROOT}/reference/dummy-utxos.json" <<'EOD'
{
  "artifact_class": "dummy-utxo-set",
  "network": "simulated-only",
  "utxos": [
    {
      "utxo_id": "dummy-utxo-0001",
      "amount_sats": 250000000,
      "status": "watch-only"
    }
  ]
}
EOD

cat > "${NODE_ROOT}/reference/fee-policy.json" <<'EOD'
{
  "artifact_class": "dummy-fee-policy",
  "feerate_sat_vb": 12,
  "network_action": "not-applicable"
}
EOD

cat > "${NODE_ROOT}/export/watchonly-bundle.json" <<'EOD'
{
  "bundle_class": "dummy-watchonly-export",
  "prepared_by_role": "watch-only-node",
  "descriptor_ref": "descriptor-template.json",
  "utxo_ref": "dummy-utxos.json",
  "fee_policy_ref": "fee-policy.json",
  "signing_material": "absent",
  "secrets_present": false
}
EOD

chmod 0640 \
  "${NODE_ROOT}/reference/descriptor-template.json" \
  "${NODE_ROOT}/reference/dummy-utxos.json" \
  "${NODE_ROOT}/reference/fee-policy.json" \
  "${NODE_ROOT}/export/watchonly-bundle.json"

ss -ltnup > "${VALIDATION_DIR}/listeners.txt"
ps -eo pid,comm,args > "${VALIDATION_DIR}/processes.txt"

{
  echo "guest=vm-bitcoin-node"
  echo "role=node-watchonly"
  for port in 8332 8333 18332 18333 18443 18444 50001 50002 50011 50012 3000 3002; do
    if ss -H -ltnup "( sport = :${port} )" | grep -q .; then
      status="open"
    else
      status="absent"
    fi
    echo "tcp/${port}=${status}"
  done
} > "${VALIDATION_DIR}/bitcoin-listener-check.txt"

{
  if ps -eo comm= | grep -Eq '^(bitcoind|bitcoin-qt|bitcoin-cli|electrs|electrumx|fulcrum|esplora|addrindexrs|ord)$'; then
    echo "bitcoin_daemons=present"
  else
    echo "bitcoin_daemons=absent"
  fi
} > "${VALIDATION_DIR}/bitcoin-process-check.txt"

{
  echo "wallet_dat=absent"
  echo "seed_files=absent"
  echo "xprv_files=absent"
  find "${NODE_ROOT}" /etc/ailab -xdev \
    \( -name 'wallet.dat' -o -name '*.seed' -o -name '*.xprv' -o -name '*seed*' -o -name '*private-key*' \) -print || true
} > "${VALIDATION_DIR}/forbidden-artifacts.txt"

stat -c '%a %U %G %n' \
  "${STATE_DIR}" \
  "${NODE_ROOT}" \
  "${NODE_ROOT}/reference" \
  "${NODE_ROOT}/export" \
  "${NODE_ROOT}/validation" \
  "${NODE_ROOT}/reference/descriptor-template.json" \
  "${NODE_ROOT}/reference/dummy-utxos.json" \
  "${NODE_ROOT}/reference/fee-policy.json" \
  "${NODE_ROOT}/export/watchonly-bundle.json" \
  /etc/ailab/bitcoin-dummy-only.txt \
  /usr/local/sbin/ailab-bitcoin-node-export.sh \
  > "${VALIDATION_DIR}/permissions.txt"

cat > "${VALIDATION_DIR}/role-separation.txt" <<'EOD'
role=node-watchonly
exports_watchonly_bundle=yes
stores_unsigned_psbt=no
stores_signed_psbt=no
stores_broadcast_receipt=no
stores_real_signing_material=no
EOD

dpkg-query -W > /var/log/ailab/section-06-package-manifest.txt
touch "${STATE_DIR}/section-06-complete.done"
systemctl poweroff --no-wall || poweroff -f
EOF
  chmod 0755 "${root_dir}/usr/local/sbin/ailab-bitcoin-node-export.sh"

  cat > "${root_dir}/etc/systemd/system/ailab-bitcoin-node-export.service" <<'EOF'
[Unit]
Description=Ailab dummy Bitcoin node export
ConditionPathExists=!/var/lib/ailab/bitcoin-sim/section-06-complete.done
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ailab-bitcoin-node-export.sh
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

  ln -sf /etc/systemd/system/ailab-bitcoin-node-export.service \
    "${root_dir}/etc/systemd/system/multi-user.target.wants/ailab-bitcoin-node-export.service"

  cat > "${root_dir}/etc/ailab/bitcoin-role.txt" <<'EOF'
role=node-watchonly
zone=bitcoin-simulation
allowed_data=dummy-watchonly-bundles,dummy-utxo-reference,dummy-fee-policy
forbidden_data=real-seeds,real-xprv,wallet.dat,productive-private-keys,productive-api-keys,signed-psbt-storage
EOF
  chmod 0640 "${root_dir}/etc/ailab/bitcoin-role.txt"

  relax_boot_efi_fstab "${root_dir}"
}

configure_service_offline() {
  local root_dir="$1"

  rm -rf \
    "${root_dir}/var/lib/ailab/bitcoin-sim" \
    "${root_dir}/srv/bitcoin-sim/service/inbox" \
    "${root_dir}/srv/bitcoin-sim/service/reference" \
    "${root_dir}/srv/bitcoin-sim/service/work" \
    "${root_dir}/srv/bitcoin-sim/service/import" \
    "${root_dir}/srv/bitcoin-sim/service/outbox" \
    "${root_dir}/srv/bitcoin-sim/service/archive" \
    "${root_dir}/srv/bitcoin-sim/service/validation"
  rm -f \
    "${root_dir}/usr/local/sbin/ailab-bitcoin-service-worker.sh" \
    "${root_dir}/usr/local/sbin/ailab-bitcoin-service-orchestrator.sh" \
    "${root_dir}/etc/systemd/system/ailab-bitcoin-service.service" \
    "${root_dir}/etc/systemd/system/multi-user.target.wants/ailab-bitcoin-service.service" \
    "${root_dir}/var/log/ailab/section-06-service.log" \
    "${root_dir}/var/log/ailab/section-06-package-manifest.txt"

  chroot "${root_dir}" /bin/bash -lc "
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    if ! getent passwd btcpayout >/dev/null; then
      adduser --system --group --home /nonexistent --no-create-home --shell /usr/sbin/nologin btcpayout
    fi
    passwd -l btcpayout >/dev/null 2>&1 || true
    install -d -m 0750 -o root -g root /var/lib/ailab/bitcoin-sim
    install -d -m 0750 -o root -g btcpayout /srv/bitcoin-sim/service
    install -d -m 0770 -o root -g btcpayout /srv/bitcoin-sim/service/inbox /srv/bitcoin-sim/service/inbox/requests
    install -d -m 0750 -o root -g btcpayout /srv/bitcoin-sim/service/reference
    install -d -m 0770 -o root -g btcpayout /srv/bitcoin-sim/service/work /srv/bitcoin-sim/service/work/unsigned-psbt
    install -d -m 0750 -o root -g btcpayout /srv/bitcoin-sim/service/import /srv/bitcoin-sim/service/import/signed
    install -d -m 0770 -o root -g btcpayout /srv/bitcoin-sim/service/outbox /srv/bitcoin-sim/service/outbox/receipts
    install -d -m 0700 -o root -g root /srv/bitcoin-sim/service/archive
    install -d -m 0750 -o root -g root /srv/bitcoin-sim/service/validation
  "

  cat > "${root_dir}/usr/local/sbin/ailab-bitcoin-service-worker.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
umask 027

SERVICE_ROOT="/srv/bitcoin-sim/service"
REQUEST_FILE="${SERVICE_ROOT}/inbox/requests/payout-0001.json"
REFERENCE_FILE="${SERVICE_ROOT}/reference/watchonly-bundle.json"
UNSIGNED_FILE="${SERVICE_ROOT}/work/unsigned-psbt/payout-0001-unsigned.psbt.json"
SIGNED_FILE="${SERVICE_ROOT}/import/signed/payout-0001-signed.psbt.json"
RECEIPT_FILE="${SERVICE_ROOT}/outbox/receipts/payout-0001-broadcast.json"
STATE_FILE="${SERVICE_ROOT}/work/workflow-state.txt"

phase="waiting-for-input"

if [[ -f "${REQUEST_FILE}" && -f "${REFERENCE_FILE}" && ! -f "${UNSIGNED_FILE}" ]]; then
  cat > "${UNSIGNED_FILE}" <<'EOD'
{
  "artifact_class": "dummy-unsigned-psbt",
  "request_id": "payout-0001",
  "prepared_by_role": "hot-service",
  "source_bundle": "watchonly-bundle.json",
  "signing_required_from": "offline-cold-signer-simulated",
  "network_action": "not-performed",
  "real_signing_material_present": false
}
EOD
  chmod 0640 "${UNSIGNED_FILE}"
  phase="phase1-unsigned"
fi

if [[ -f "${SIGNED_FILE}" && -f "${UNSIGNED_FILE}" && ! -f "${RECEIPT_FILE}" ]]; then
  cat > "${RECEIPT_FILE}" <<'EOD'
{
  "artifact_class": "dummy-broadcast-receipt",
  "request_id": "payout-0001",
  "prepared_by_role": "hot-service",
  "signed_input": "payout-0001-signed.psbt.json",
  "broadcast_mode": "simulated-no-network",
  "network_action": "not-performed",
  "result": "dummy-accepted-for-simulation"
}
EOD
  chmod 0640 "${RECEIPT_FILE}"
  phase="phase2-import-broadcast"
fi

cat > "${STATE_FILE}" <<EOD
phase=${phase}
request_present=$([[ -f "${REQUEST_FILE}" ]] && echo yes || echo no)
reference_present=$([[ -f "${REFERENCE_FILE}" ]] && echo yes || echo no)
unsigned_present=$([[ -f "${UNSIGNED_FILE}" ]] && echo yes || echo no)
signed_present=$([[ -f "${SIGNED_FILE}" ]] && echo yes || echo no)
receipt_present=$([[ -f "${RECEIPT_FILE}" ]] && echo yes || echo no)
EOD
chmod 0640 "${STATE_FILE}"
EOF
  chmod 0755 "${root_dir}/usr/local/sbin/ailab-bitcoin-service-worker.sh"

  cat > "${root_dir}/usr/local/sbin/ailab-bitcoin-service-orchestrator.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
umask 027

exec >>/var/log/ailab/section-06-service.log 2>&1

STATE_DIR="/var/lib/ailab/bitcoin-sim"
SERVICE_ROOT="/srv/bitcoin-sim/service"
VALIDATION_DIR="${SERVICE_ROOT}/validation"
STATE_FILE="${SERVICE_ROOT}/work/workflow-state.txt"

install -d -m 0750 "${STATE_DIR}" "${VALIDATION_DIR}" /var/log/ailab

runuser -u btcpayout -- /usr/local/sbin/ailab-bitcoin-service-worker.sh

phase="$(awk -F= '/^phase=/{print $2}' "${STATE_FILE}" 2>/dev/null || echo waiting-for-input)"

ss -ltnup > "${VALIDATION_DIR}/${phase}-listeners.txt"
ps -eo pid,comm,args > "${VALIDATION_DIR}/${phase}-processes.txt"

{
  echo "guest=vm-bitcoin-service"
  echo "role=hot-service-simulation"
  echo "phase=${phase}"
  for port in 8332 8333 18332 18333 18443 18444 50001 50002 50011 50012 3000 3002; do
    if ss -H -ltnup "( sport = :${port} )" | grep -q .; then
      status="open"
    else
      status="absent"
    fi
    echo "tcp/${port}=${status}"
  done
} > "${VALIDATION_DIR}/${phase}-bitcoin-listener-check.txt"

{
  if ps -eo comm= | grep -Eq '^(bitcoind|bitcoin-qt|bitcoin-cli|electrs|electrumx|fulcrum|esplora|addrindexrs|ord)$'; then
    echo "bitcoin_daemons=present"
  else
    echo "bitcoin_daemons=absent"
  fi
} > "${VALIDATION_DIR}/${phase}-bitcoin-process-check.txt"

{
  echo "wallet_dat=absent"
  echo "seed_files=absent"
  echo "xprv_files=absent"
  find "${SERVICE_ROOT}" /etc/ailab -xdev \
    \( -name 'wallet.dat' -o -name '*.seed' -o -name '*.xprv' -o -name '*seed*' -o -name '*private-key*' \) -print || true
} > "${VALIDATION_DIR}/${phase}-forbidden-artifacts.txt"

stat -c '%a %U %G %n' \
  "${STATE_DIR}" \
  "${SERVICE_ROOT}" \
  "${SERVICE_ROOT}/inbox" \
  "${SERVICE_ROOT}/inbox/requests" \
  "${SERVICE_ROOT}/reference" \
  "${SERVICE_ROOT}/work" \
  "${SERVICE_ROOT}/work/unsigned-psbt" \
  "${SERVICE_ROOT}/import" \
  "${SERVICE_ROOT}/import/signed" \
  "${SERVICE_ROOT}/outbox" \
  "${SERVICE_ROOT}/outbox/receipts" \
  "${SERVICE_ROOT}/archive" \
  "${SERVICE_ROOT}/validation" \
  /etc/ailab/bitcoin-role.txt \
  /usr/local/sbin/ailab-bitcoin-service-worker.sh \
  /usr/local/sbin/ailab-bitcoin-service-orchestrator.sh \
  > "${VALIDATION_DIR}/${phase}-permissions.txt"

{
  echo "role=hot-service-simulation"
  echo "phase=${phase}"
  echo "stores_watchonly_bundle=$([[ -f "${SERVICE_ROOT}/reference/watchonly-bundle.json" ]] && echo yes || echo no)"
  echo "stores_unsigned_psbt=$([[ -f "${SERVICE_ROOT}/work/unsigned-psbt/payout-0001-unsigned.psbt.json" ]] && echo yes || echo no)"
  echo "stores_signed_psbt_import=$([[ -f "${SERVICE_ROOT}/import/signed/payout-0001-signed.psbt.json" ]] && echo yes || echo no)"
  echo "stores_broadcast_receipt=$([[ -f "${SERVICE_ROOT}/outbox/receipts/payout-0001-broadcast.json" ]] && echo yes || echo no)"
  echo "stores_real_signing_material=no"
} > "${VALIDATION_DIR}/${phase}-role-separation.txt"

cp "${STATE_FILE}" "${VALIDATION_DIR}/${phase}-workflow-state.txt"
dpkg-query -W > /var/log/ailab/section-06-package-manifest.txt

if [[ "${phase}" == "phase1-unsigned" ]]; then
  touch "${STATE_DIR}/phase1.done"
else
  if [[ "${phase}" == "phase2-import-broadcast" ]]; then
    touch "${STATE_DIR}/section-06-complete.done"
  fi
fi

systemctl poweroff --no-wall || poweroff -f
EOF
  chmod 0755 "${root_dir}/usr/local/sbin/ailab-bitcoin-service-orchestrator.sh"

  cat > "${root_dir}/etc/systemd/system/ailab-bitcoin-service.service" <<'EOF'
[Unit]
Description=Ailab dummy Bitcoin service workflow
ConditionPathExists=!/var/lib/ailab/bitcoin-sim/section-06-complete.done
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ailab-bitcoin-service-orchestrator.sh
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

  ln -sf /etc/systemd/system/ailab-bitcoin-service.service \
    "${root_dir}/etc/systemd/system/multi-user.target.wants/ailab-bitcoin-service.service"

  cat > "${root_dir}/etc/ailab/bitcoin-role.txt" <<'EOF'
role=hot-service-simulation
zone=bitcoin-simulation
allowed_data=dummy-payout-requests,dummy-watchonly-bundle,dummy-unsigned-psbt,dummy-signed-import-placeholder,dummy-broadcast-receipts
forbidden_data=real-seeds,real-xprv,wallet.dat,productive-private-keys,productive-api-keys,offline-cold-secrets
EOF
  chmod 0640 "${root_dir}/etc/ailab/bitcoin-role.txt"

  relax_boot_efi_fstab "${root_dir}"
}

prepare_guest_disks() {
  local vmid="$1"
  local mode="$2"
  local root_dir="${TMP_ROOT}/mnt-${vmid}-rw"
  local loopdev=""

  ensure_vm_stopped "${vmid}"
  loopdev="$(mount_vm_rw "${vmid}" "${root_dir}")"
  if [[ "${mode}" == "node" ]]; then
    configure_node_offline "${root_dir}"
  else
    configure_service_offline "${root_dir}"
  fi
  cleanup_vm_mount "${root_dir}" "${loopdev}"
}

assert_guest_marker() {
  local vmid="$1"
  local marker="$2"
  local root_dir="${TMP_ROOT}/probe-${vmid}"
  local loopdev

  loopdev="$(mount_vm_ro "${vmid}" "${root_dir}")"
  [[ -f "${root_dir}${marker}" ]] || {
    cleanup_vm_mount "${root_dir}" "${loopdev}"
    fail "VM ${vmid} is missing marker ${marker}."
  }
  cleanup_vm_mount "${root_dir}" "${loopdev}"
}

run_guest_once() {
  local vmid="$1"
  local marker="$2"
  local attempts="${3:-180}"

  qm start "${vmid}" >/dev/null
  if ! wait_for_vm_state "${vmid}" stopped "${attempts}" 2; then
    log "VM ${vmid} did not stop in time; forcing stop for inspection."
    qm stop "${vmid}" --skiplock 1 >/dev/null 2>&1 || true
    wait_for_vm_state "${vmid}" stopped 60 2 || fail "VM ${vmid} did not stop after forced stop."
  fi
  assert_guest_marker "${vmid}" "${marker}"
}

extract_node_results() {
  local root_dir="${TMP_ROOT}/extract-${NODE_VMID}"
  local loopdev

  loopdev="$(mount_vm_ro "${NODE_VMID}" "${root_dir}")"
  cp "${root_dir}/srv/bitcoin-sim/node/export/watchonly-bundle.json" "${VALIDATION_DIR}/203-watchonly-bundle.json"
  cp "${root_dir}/srv/bitcoin-sim/node/validation/listeners.txt" "${VALIDATION_DIR}/203-node-listeners.txt"
  cp "${root_dir}/srv/bitcoin-sim/node/validation/processes.txt" "${VALIDATION_DIR}/203-node-processes.txt"
  cp "${root_dir}/srv/bitcoin-sim/node/validation/bitcoin-listener-check.txt" "${VALIDATION_DIR}/203-node-bitcoin-listener-check.txt"
  cp "${root_dir}/srv/bitcoin-sim/node/validation/bitcoin-process-check.txt" "${VALIDATION_DIR}/203-node-bitcoin-process-check.txt"
  cp "${root_dir}/srv/bitcoin-sim/node/validation/forbidden-artifacts.txt" "${VALIDATION_DIR}/203-node-forbidden-artifacts.txt"
  cp "${root_dir}/srv/bitcoin-sim/node/validation/permissions.txt" "${VALIDATION_DIR}/203-node-permissions.txt"
  cp "${root_dir}/srv/bitcoin-sim/node/validation/role-separation.txt" "${VALIDATION_DIR}/203-node-role-separation.txt"
  cp "${root_dir}/var/log/ailab/section-06-package-manifest.txt" "${MANIFEST_DIR}/203-vm-bitcoin-node-section06-packages.txt"
  cp "${root_dir}/var/log/ailab/section-06-node.log" "${VALIDATION_DIR}/203-node-run.log"
  cleanup_vm_mount "${root_dir}" "${loopdev}"

  install -m 0600 "${VALIDATION_DIR}/203-watchonly-bundle.json" "${RUNTIME_ROOT}/watchonly-export/watchonly-bundle.json"
}

inject_service_phase1_inputs() {
  local root_dir="${TMP_ROOT}/inject-${SERVICE_VMID}-phase1"
  local loopdev

  loopdev="$(mount_vm_rw "${SERVICE_VMID}" "${root_dir}")"
  install -m 0640 "${RUNTIME_ROOT}/watchonly-export/watchonly-bundle.json" \
    "${root_dir}/srv/bitcoin-sim/service/reference/watchonly-bundle.json"
  cat > "${root_dir}/srv/bitcoin-sim/service/inbox/requests/payout-0001.json" <<'EOF'
{
  "request_id": "payout-0001",
  "prepared_by_role": "hot-service",
  "beneficiary_label": "dummy-beneficiary-001",
  "amount_sats": 100000,
  "note": "simulation-only-no-broadcast"
}
EOF
  chroot "${root_dir}" /bin/bash -lc "
    chown root:btcpayout /srv/bitcoin-sim/service/reference/watchonly-bundle.json /srv/bitcoin-sim/service/inbox/requests/payout-0001.json
    chmod 0640 /srv/bitcoin-sim/service/reference/watchonly-bundle.json /srv/bitcoin-sim/service/inbox/requests/payout-0001.json
  "
  cleanup_vm_mount "${root_dir}" "${loopdev}"
}

extract_service_phase1_results() {
  local root_dir="${TMP_ROOT}/extract-${SERVICE_VMID}-phase1"
  local loopdev

  loopdev="$(mount_vm_ro "${SERVICE_VMID}" "${root_dir}")"
  cp "${root_dir}/srv/bitcoin-sim/service/work/unsigned-psbt/payout-0001-unsigned.psbt.json" \
    "${VALIDATION_DIR}/204-service-unsigned-psbt.json"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase1-unsigned-listeners.txt" \
    "${VALIDATION_DIR}/204-service-phase1-listeners.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase1-unsigned-processes.txt" \
    "${VALIDATION_DIR}/204-service-phase1-processes.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase1-unsigned-bitcoin-listener-check.txt" \
    "${VALIDATION_DIR}/204-service-phase1-bitcoin-listener-check.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase1-unsigned-bitcoin-process-check.txt" \
    "${VALIDATION_DIR}/204-service-phase1-bitcoin-process-check.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase1-unsigned-forbidden-artifacts.txt" \
    "${VALIDATION_DIR}/204-service-phase1-forbidden-artifacts.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase1-unsigned-permissions.txt" \
    "${VALIDATION_DIR}/204-service-phase1-permissions.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase1-unsigned-role-separation.txt" \
    "${VALIDATION_DIR}/204-service-phase1-role-separation.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase1-unsigned-workflow-state.txt" \
    "${VALIDATION_DIR}/204-service-phase1-workflow-state.txt"
  cp "${root_dir}/var/log/ailab/section-06-package-manifest.txt" \
    "${MANIFEST_DIR}/204-vm-bitcoin-service-section06-packages.txt"
  cp "${root_dir}/var/log/ailab/section-06-service.log" \
    "${VALIDATION_DIR}/204-service-run-phase1.log"
  cleanup_vm_mount "${root_dir}" "${loopdev}"

  install -m 0600 "${VALIDATION_DIR}/204-service-unsigned-psbt.json" \
    "${RUNTIME_ROOT}/unsigned/payout-0001-unsigned.psbt.json"
}

create_dummy_signed_artifact() {
  cat > "${RUNTIME_ROOT}/signed/payout-0001-signed.psbt.json" <<'EOF'
{
  "artifact_class": "dummy-signed-psbt",
  "request_id": "payout-0001",
  "prepared_by_role": "offline-cold-signer-simulated",
  "signature_material": "DUMMY_SIGNATURE_MARKER_ONLY",
  "approval_scope": "simulation-only",
  "real_private_keys_present": false
}
EOF
  chmod 0600 "${RUNTIME_ROOT}/signed/payout-0001-signed.psbt.json"
}

inject_service_phase2_input() {
  local root_dir="${TMP_ROOT}/inject-${SERVICE_VMID}-phase2"
  local loopdev

  loopdev="$(mount_vm_rw "${SERVICE_VMID}" "${root_dir}")"
  install -m 0640 "${RUNTIME_ROOT}/signed/payout-0001-signed.psbt.json" \
    "${root_dir}/srv/bitcoin-sim/service/import/signed/payout-0001-signed.psbt.json"
  chroot "${root_dir}" /bin/bash -lc "
    chown root:btcpayout /srv/bitcoin-sim/service/import/signed/payout-0001-signed.psbt.json
    chmod 0640 /srv/bitcoin-sim/service/import/signed/payout-0001-signed.psbt.json
  "
  cleanup_vm_mount "${root_dir}" "${loopdev}"
}

extract_service_phase2_results() {
  local root_dir="${TMP_ROOT}/extract-${SERVICE_VMID}-phase2"
  local loopdev

  loopdev="$(mount_vm_ro "${SERVICE_VMID}" "${root_dir}")"
  cp "${root_dir}/srv/bitcoin-sim/service/outbox/receipts/payout-0001-broadcast.json" \
    "${VALIDATION_DIR}/204-service-broadcast-receipt.json"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase2-import-broadcast-listeners.txt" \
    "${VALIDATION_DIR}/204-service-phase2-listeners.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase2-import-broadcast-processes.txt" \
    "${VALIDATION_DIR}/204-service-phase2-processes.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase2-import-broadcast-bitcoin-listener-check.txt" \
    "${VALIDATION_DIR}/204-service-phase2-bitcoin-listener-check.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase2-import-broadcast-bitcoin-process-check.txt" \
    "${VALIDATION_DIR}/204-service-phase2-bitcoin-process-check.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase2-import-broadcast-forbidden-artifacts.txt" \
    "${VALIDATION_DIR}/204-service-phase2-forbidden-artifacts.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase2-import-broadcast-permissions.txt" \
    "${VALIDATION_DIR}/204-service-phase2-permissions.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase2-import-broadcast-role-separation.txt" \
    "${VALIDATION_DIR}/204-service-phase2-role-separation.txt"
  cp "${root_dir}/srv/bitcoin-sim/service/validation/phase2-import-broadcast-workflow-state.txt" \
    "${VALIDATION_DIR}/204-service-phase2-workflow-state.txt"
  cp "${root_dir}/var/log/ailab/section-06-service.log" \
    "${VALIDATION_DIR}/204-service-run-phase2.log"
  cleanup_vm_mount "${root_dir}" "${loopdev}"

  install -m 0600 "${VALIDATION_DIR}/204-service-broadcast-receipt.json" \
    "${RUNTIME_ROOT}/receipts/payout-0001-broadcast.json"
}

write_host_validation() {
  stat -c '%a %U %G %n' \
    /root/ailab-runtime \
    "${RUNTIME_ROOT}" \
    "${RUNTIME_ROOT}/watchonly-export" \
    "${RUNTIME_ROOT}/unsigned" \
    "${RUNTIME_ROOT}/signed" \
    "${RUNTIME_ROOT}/receipts" \
    "${RUNTIME_ROOT}/logs" \
    "${RUNTIME_ROOT}/watchonly-export/watchonly-bundle.json" \
    "${RUNTIME_ROOT}/unsigned/payout-0001-unsigned.psbt.json" \
    "${RUNTIME_ROOT}/signed/payout-0001-signed.psbt.json" \
    "${RUNTIME_ROOT}/receipts/payout-0001-broadcast.json" \
    > "${VALIDATION_DIR}/host-runtime-permissions.txt"

  {
    echo "watchonly_bundle_root_only=$(stat -c '%a:%U:%G' "${RUNTIME_ROOT}/watchonly-export/watchonly-bundle.json")"
    echo "unsigned_psbt_root_only=$(stat -c '%a:%U:%G' "${RUNTIME_ROOT}/unsigned/payout-0001-unsigned.psbt.json")"
    echo "signed_psbt_root_only=$(stat -c '%a:%U:%G' "${RUNTIME_ROOT}/signed/payout-0001-signed.psbt.json")"
    echo "receipt_root_only=$(stat -c '%a:%U:%G' "${RUNTIME_ROOT}/receipts/payout-0001-broadcast.json")"
  } > "${VALIDATION_DIR}/host-runtime-summary.txt"

  qm list > "${VALIDATION_DIR}/qm-list-after-section06.txt"
  qm config "${NODE_VMID}" > "${VALIDATION_DIR}/203-final-config.txt"
  qm config "${SERVICE_VMID}" > "${VALIDATION_DIR}/204-final-config.txt"
  qm status "${NODE_VMID}" > "${VALIDATION_DIR}/203-final-status.txt"
  qm status "${SERVICE_VMID}" > "${VALIDATION_DIR}/204-final-status.txt"
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  grep -Fqx "${pattern}" "${file}" || fail "Expected '${pattern}' in ${file}."
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  ! grep -Fq "${pattern}" "${file}" || fail "Unexpected '${pattern}' in ${file}."
}

validate_results() {
  log "Validating section 06 artifacts."

  for file in \
    "${VALIDATION_DIR}/203-node-bitcoin-listener-check.txt" \
    "${VALIDATION_DIR}/204-service-phase1-bitcoin-listener-check.txt" \
    "${VALIDATION_DIR}/204-service-phase2-bitcoin-listener-check.txt"; do
    for port in 8332 8333 18332 18333 18443 18444 50001 50002 50011 50012 3000 3002; do
      assert_contains "${file}" "tcp/${port}=absent"
    done
  done

  for file in \
    "${VALIDATION_DIR}/203-node-bitcoin-process-check.txt" \
    "${VALIDATION_DIR}/204-service-phase1-bitcoin-process-check.txt" \
    "${VALIDATION_DIR}/204-service-phase2-bitcoin-process-check.txt"; do
    assert_contains "${file}" "bitcoin_daemons=absent"
  done

  assert_contains "${VALIDATION_DIR}/203-node-role-separation.txt" "role=node-watchonly"
  assert_contains "${VALIDATION_DIR}/203-node-role-separation.txt" "exports_watchonly_bundle=yes"
  assert_contains "${VALIDATION_DIR}/203-node-role-separation.txt" "stores_unsigned_psbt=no"
  assert_contains "${VALIDATION_DIR}/203-node-role-separation.txt" "stores_signed_psbt=no"
  assert_contains "${VALIDATION_DIR}/203-node-role-separation.txt" "stores_broadcast_receipt=no"
  assert_contains "${VALIDATION_DIR}/203-node-role-separation.txt" "stores_real_signing_material=no"

  assert_contains "${VALIDATION_DIR}/204-service-phase1-workflow-state.txt" "phase=phase1-unsigned"
  assert_contains "${VALIDATION_DIR}/204-service-phase1-workflow-state.txt" "request_present=yes"
  assert_contains "${VALIDATION_DIR}/204-service-phase1-workflow-state.txt" "reference_present=yes"
  assert_contains "${VALIDATION_DIR}/204-service-phase1-workflow-state.txt" "unsigned_present=yes"
  assert_contains "${VALIDATION_DIR}/204-service-phase1-workflow-state.txt" "signed_present=no"
  assert_contains "${VALIDATION_DIR}/204-service-phase1-workflow-state.txt" "receipt_present=no"

  assert_contains "${VALIDATION_DIR}/204-service-phase2-workflow-state.txt" "phase=phase2-import-broadcast"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-workflow-state.txt" "request_present=yes"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-workflow-state.txt" "reference_present=yes"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-workflow-state.txt" "unsigned_present=yes"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-workflow-state.txt" "signed_present=yes"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-workflow-state.txt" "receipt_present=yes"

  assert_contains "${VALIDATION_DIR}/204-service-phase1-role-separation.txt" "phase=phase1-unsigned"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-role-separation.txt" "phase=phase2-import-broadcast"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-role-separation.txt" "stores_real_signing_material=no"

  assert_contains "${VALIDATION_DIR}/203-node-permissions.txt" "750 root root /var/lib/ailab/bitcoin-sim"
  assert_contains "${VALIDATION_DIR}/203-node-permissions.txt" "750 root root /srv/bitcoin-sim/node"
  assert_contains "${VALIDATION_DIR}/203-node-permissions.txt" "750 root root /srv/bitcoin-sim/node/reference"
  assert_contains "${VALIDATION_DIR}/203-node-permissions.txt" "750 root root /srv/bitcoin-sim/node/export"
  assert_contains "${VALIDATION_DIR}/203-node-permissions.txt" "640 root root /srv/bitcoin-sim/node/export/watchonly-bundle.json"

  assert_contains "${VALIDATION_DIR}/204-service-phase2-permissions.txt" "750 root btcpayout /srv/bitcoin-sim/service"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-permissions.txt" "770 root btcpayout /srv/bitcoin-sim/service/inbox/requests"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-permissions.txt" "750 root btcpayout /srv/bitcoin-sim/service/reference"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-permissions.txt" "770 root btcpayout /srv/bitcoin-sim/service/work/unsigned-psbt"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-permissions.txt" "750 root btcpayout /srv/bitcoin-sim/service/import/signed"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-permissions.txt" "770 root btcpayout /srv/bitcoin-sim/service/outbox/receipts"
  assert_contains "${VALIDATION_DIR}/204-service-phase2-permissions.txt" "700 root root /srv/bitcoin-sim/service/archive"

  assert_contains "${VALIDATION_DIR}/host-runtime-permissions.txt" "700 root root ${RUNTIME_ROOT}"
  assert_contains "${VALIDATION_DIR}/host-runtime-permissions.txt" "600 root root ${RUNTIME_ROOT}/watchonly-export/watchonly-bundle.json"
  assert_contains "${VALIDATION_DIR}/host-runtime-permissions.txt" "600 root root ${RUNTIME_ROOT}/unsigned/payout-0001-unsigned.psbt.json"
  assert_contains "${VALIDATION_DIR}/host-runtime-permissions.txt" "600 root root ${RUNTIME_ROOT}/signed/payout-0001-signed.psbt.json"
  assert_contains "${VALIDATION_DIR}/host-runtime-permissions.txt" "600 root root ${RUNTIME_ROOT}/receipts/payout-0001-broadcast.json"

  for file in \
    "${VALIDATION_DIR}/203-node-forbidden-artifacts.txt" \
    "${VALIDATION_DIR}/204-service-phase1-forbidden-artifacts.txt" \
    "${VALIDATION_DIR}/204-service-phase2-forbidden-artifacts.txt"; do
    assert_contains "${file}" "wallet_dat=absent"
    assert_contains "${file}" "seed_files=absent"
    assert_contains "${file}" "xprv_files=absent"
    assert_not_contains "${file}" "wallet.dat"
    assert_not_contains "${file}" ".seed"
    assert_not_contains "${file}" ".xprv"
  done

  assert_contains "${VALIDATION_DIR}/203-final-status.txt" "status: stopped"
  assert_contains "${VALIDATION_DIR}/204-final-status.txt" "status: stopped"

  log "Section 06 validation succeeded."
}

finalize_snapshots() {
  snapshot_guest "${NODE_VMID}" "vm-bitcoin-node" "post-bitcoin-sim"
  snapshot_guest "${SERVICE_VMID}" "vm-bitcoin-service" "post-bitcoin-sim"
}

main() {
  prepare_host_paths
  log "Starting section 06 Bitcoin simulation rollout."

  prepare_snapshots
  prepare_guest_disks "${NODE_VMID}" "node"
  prepare_guest_disks "${SERVICE_VMID}" "service"

  log "Running node watch-only export validator."
  run_guest_once "${NODE_VMID}" "/var/lib/ailab/bitcoin-sim/section-06-complete.done" 240
  extract_node_results

  log "Injecting phase 1 inputs into service guest."
  inject_service_phase1_inputs
  log "Running service phase 1 unsigned-PSBT validator."
  run_guest_once "${SERVICE_VMID}" "/var/lib/ailab/bitcoin-sim/phase1.done" 420
  extract_service_phase1_results

  log "Creating simulated offline-signed artifact."
  create_dummy_signed_artifact
  inject_service_phase2_input
  log "Running service phase 2 import/broadcast validator."
  run_guest_once "${SERVICE_VMID}" "/var/lib/ailab/bitcoin-sim/section-06-complete.done" 420
  extract_service_phase2_results

  write_host_validation
  validate_results
  finalize_snapshots
  log "Section 06 Bitcoin simulation completed successfully."
}

main "$@"
