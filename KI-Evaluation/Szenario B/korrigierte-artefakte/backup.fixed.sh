#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="/srv/backups/sanitized"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}"
STAGING_DIR="$(mktemp -d "${BACKUP_ROOT}/.staging.${STAMP}.XXXXXX")"
LOCKFILE="/run/lock/ailab-sanitized-backup.lock"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
BACKUP_AGE_RECIPIENT="${BACKUP_AGE_RECIPIENT:?set an offline-controlled age recipient}"

umask 077
install -d -m 700 "$BACKUP_ROOT"
install -d -m 700 "$(dirname "$LOCKFILE")"

exec 9>"$LOCKFILE"
flock -n 9 || {
  echo "backup already running" >&2
  exit 1
}

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

for cmd in age flock pct sha256sum tar vzdump; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "missing command: $cmd" >&2
    exit 1
  }
done

for guest in 201 202 203 204; do
  pct status "$guest" >/dev/null 2>&1 || {
    echo "guest $guest is missing or inaccessible" >&2
    exit 1
  }
done

cat > "${STAGING_DIR}/EXCLUSIONS.txt" <<'EOF'
This workflow is intentionally sanitized.

Never include:
- /var/lib/tor
- hidden-service identities
- client auth material
- /var/lib/bitcoind
- wallet.dat
- wallet directories
- seed files
- xprv material
- raw private keys
- rpc cookie files
EOF

cat > "${STAGING_DIR}/RESTORE-NOTES.txt" <<'EOF'
Restore intent:
1. Restore sanitized configuration and guest metadata only.
2. Rebuild Tor hidden-service identities and Bitcoin private material outside this backup path.
3. Validate guest configs before starting services.
4. Treat approved vzdump archives as workload restores for low-sensitivity guests only.
EOF

for guest in 201 202 203 204; do
  pct config "$guest" > "${STAGING_DIR}/pct-config-${guest}.txt"
done

echo "Backing up sanitized tor-edge configuration"
pct exec 201 -- tar -C / -czf - \
  etc/caddy \
  etc/tor \
> "${STAGING_DIR}/tor-edge-config-sanitized.tar.gz"

echo "Backing up sanitized btc-node configuration"
pct exec 204 -- tar -C / -czf - \
  etc/bitcoin \
> "${STAGING_DIR}/btc-node-config-sanitized.tar.gz"

echo "Running approved guest backups"
install -d -m 700 "${STAGING_DIR}/vzdump"
vzdump 202 203 --mode snapshot --compress zstd --dumpdir "${STAGING_DIR}/vzdump"

(
  cd "$STAGING_DIR"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)

echo "Encrypting final backup bundle"
tar -C "$STAGING_DIR" -czf - . \
  | age -r "$BACKUP_AGE_RECIPIENT" \
  > "${BACKUP_DIR}.tar.gz.age"

sha256sum "${BACKUP_DIR}.tar.gz.age" > "${BACKUP_DIR}.tar.gz.age.sha256"
chmod 600 "${BACKUP_DIR}.tar.gz.age" "${BACKUP_DIR}.tar.gz.age.sha256"

echo "Applying simple retention"
find "$BACKUP_ROOT" -maxdepth 1 -type f -name '*.tar.gz.age' -mtime +"$RETENTION_DAYS" -delete
find "$BACKUP_ROOT" -maxdepth 1 -type f -name '*.tar.gz.age.sha256' -mtime +"$RETENTION_DAYS" -delete

echo "Backup finished: ${BACKUP_DIR}.tar.gz.age"
