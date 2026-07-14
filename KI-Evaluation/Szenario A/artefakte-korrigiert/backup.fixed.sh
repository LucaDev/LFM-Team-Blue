#!/usr/bin/env bash
set -euo pipefail

umask 077

BACKUP_ROOT="${BACKUP_ROOT:-/srv/backups/homelab}"
KEEP_RUNS="${KEEP_RUNS:-7}"
LOCK_FILE="${LOCK_FILE:-/run/lock/homelab-backup.lock}"
EXPORT_SENSITIVE="${EXPORT_SENSITIVE:-0}"
SENSITIVE_BACKUP_AGE_RECIPIENT="${SENSITIVE_BACKUP_AGE_RECIPIENT:-}"

log() {
  printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "Missing required command: $1"
    exit 1
  }
}

require_container() {
  pct status "$1" >/dev/null 2>&1 || {
    log "Required container is not available or not running: $1"
    exit 1
  }
}

[[ "$BACKUP_ROOT" == /* ]] || {
  log "BACKUP_ROOT must be an absolute path"
  exit 1
}

for cmd in age find flock ln pct sha256sum sort tar vzdump xargs; do
  if [[ "$cmd" == "age" && "$EXPORT_SENSITIVE" != "1" ]]; then
    continue
  fi
  require_cmd "$cmd"
done

if [[ "$EXPORT_SENSITIVE" == "1" && -z "$SENSITIVE_BACKUP_AGE_RECIPIENT" ]]; then
  log "EXPORT_SENSITIVE=1 requires SENSITIVE_BACKUP_AGE_RECIPIENT"
  exit 1
fi

require_container 201
require_container 202
require_container 203
require_container 204

mkdir -p "$BACKUP_ROOT" "$(dirname "$LOCK_FILE")"
chmod 700 "$BACKUP_ROOT"

exec 9>"$LOCK_FILE"
flock -n 9 || {
  log "Another backup run is already active"
  exit 1
}

RUN_ID="$(date -u +%Y%m%d-%H%M%S)"
RUN_DIR="${BACKUP_ROOT}/${RUN_ID}"
CONFIG_DIR="${RUN_DIR}/configs"
VZDUMP_DIR="${RUN_DIR}/vzdump"
SENSITIVE_DIR="${RUN_DIR}/sensitive"
RESTORE_FILE="${RUN_DIR}/RESTORE.txt"

mkdir -p "$CONFIG_DIR" "$VZDUMP_DIR"
chmod 700 "$RUN_DIR" "$CONFIG_DIR" "$VZDUMP_DIR"

cat > "$RESTORE_FILE" <<'EOF'
tor-edge-config.tar.gz
- Contains only /etc/caddy and /etc/tor.
- Hidden-service private keys are excluded from routine backups.

btc-node-config.tar.gz
- Contains only /etc/bitcoin.
- Wallet private keys and blockchain data are excluded from routine backups.

vzdump/
- Contains snapshot backups for containers 202 and 203.

sensitive/
- Optional encrypted exports.
- Created only when EXPORT_SENSITIVE=1 and an age recipient is configured.
EOF

log "Backing up tor-edge configuration without hidden-service private keys"
pct exec 201 -- tar -C / -czf - etc/caddy etc/tor \
  > "${CONFIG_DIR}/tor-edge-config.tar.gz"
tar -tzf "${CONFIG_DIR}/tor-edge-config.tar.gz" >/dev/null

log "Backing up btc-node configuration without wallets or blockchain data"
pct exec 204 -- tar -C / -czf - etc/bitcoin \
  > "${CONFIG_DIR}/btc-node-config.tar.gz"
tar -tzf "${CONFIG_DIR}/btc-node-config.tar.gz" >/dev/null

if [[ "$EXPORT_SENSITIVE" == "1" ]]; then
  mkdir -p "$SENSITIVE_DIR"
  chmod 700 "$SENSITIVE_DIR"

  log "Exporting tor-edge identities as encrypted archive"
  pct exec 201 -- tar -C / -czf - var/lib/tor \
    | age -r "$SENSITIVE_BACKUP_AGE_RECIPIENT" \
      -o "${SENSITIVE_DIR}/tor-edge-identities.tar.gz.age"

  if pct exec 204 -- test -d /var/lib/bitcoind/wallets; then
    log "Exporting btc-node wallets as encrypted archive"
    pct exec 204 -- tar -C / -czf - var/lib/bitcoind/wallets \
      | age -r "$SENSITIVE_BACKUP_AGE_RECIPIENT" \
        -o "${SENSITIVE_DIR}/btc-node-wallets.tar.gz.age"
  else
    log "No btc-node wallet directory found; skipping encrypted wallet export"
  fi
fi

log "Running container backups for app and ops workloads"
vzdump 202 203 --mode snapshot --compress zstd --dumpdir "$VZDUMP_DIR"

log "Writing checksum manifest"
(
  cd "$RUN_DIR"
  find . -type f ! -name manifest.sha256 -print0 | sort -z | xargs -0 sha256sum
) > "${RUN_DIR}/manifest.sha256"

find "$RUN_DIR" -type d -exec chmod 700 {} \;
find "$RUN_DIR" -type f -exec chmod 600 {} \;

mapfile -t EXISTING_RUNS < <(
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort
)

if ((${#EXISTING_RUNS[@]} > KEEP_RUNS)); then
  for OLD_RUN in "${EXISTING_RUNS[@]:0:${#EXISTING_RUNS[@]}-KEEP_RUNS}"; do
    if [[ -n "$OLD_RUN" && -d "${BACKUP_ROOT}/${OLD_RUN}" && "${BACKUP_ROOT}/${OLD_RUN}" != "$RUN_DIR" ]]; then
      rm -rf -- "${BACKUP_ROOT}/${OLD_RUN}"
    fi
  done
fi

ln -sfn "$RUN_DIR" "${BACKUP_ROOT}/latest"

log "Backup finished: ${RUN_DIR}"
