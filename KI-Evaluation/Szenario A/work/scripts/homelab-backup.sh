#!/usr/bin/env bash
set -euo pipefail

umask 077

LOCK_FILE=/run/homelab-backup.lock
BACKUP_ROOT=/var/lib/homelab-backups
RUNS_DIR="$BACKUP_ROOT/runs"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$RUNS_DIR/$TIMESTAMP"
DUMP_DIR="$RUN_DIR/vzdump"
CONFIG_DIR="$RUN_DIR/configs"
MANIFEST_FILE="$RUN_DIR/manifest.txt"
LOG_FILE="$RUN_DIR/run.log"

exec 9>"$LOCK_FILE"
flock -n 9 || {
  echo "homelab-backup is already running" >&2
  exit 1
}

install -d -m 0700 "$DUMP_DIR" "$CONFIG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

run_vzdump() {
  local vmid="$1"
  (
    umask 022
    vzdump "$vmid" --mode snapshot --compress zstd --remove 0 --dumpdir "$DUMP_DIR" --tmpdir /var/tmp
  )
}

echo "START $TIMESTAMP"
echo "Running snapshot backup for CT 202"
run_vzdump 202
echo "Running snapshot backup for CT 203"
run_vzdump 203

mapfile -t vzdump_archives < <(find "$DUMP_DIR" -maxdepth 1 -type f -name 'vzdump-lxc-*.tar.zst' | sort)
if (( ${#vzdump_archives[@]} != 2 )); then
  echo "Unexpected backup archive count: ${#vzdump_archives[@]}" >&2
  exit 1
fi

echo "Verifying vzdump archives"
for archive in "${vzdump_archives[@]}"; do
  chown root:root "$archive"
  chmod 0600 "$archive"
  zstd -q -t "$archive"
  sha256sum "$archive" >>"$MANIFEST_FILE"
done

TOR_EDGE_CONFIG_ARCHIVE="$CONFIG_DIR/tor-edge-config-$TIMESTAMP.tar.gz"
echo "Creating tor-edge config-only backup without hidden-service private keys"
pct exec 201 -- sh -lc \
  "tar -C / -czf - \
    etc/caddy \
    etc/default/prometheus-node-exporter \
    etc/systemd/system/homelab-onion-selftest.service \
    etc/systemd/system/homelab-onion-selftest.timer \
    etc/tor/torrc \
    etc/tor/torrc.d \
    usr/local/sbin/homelab-onion-selftest.sh" \
  >"$TOR_EDGE_CONFIG_ARCHIVE"

tar -tzf "$TOR_EDGE_CONFIG_ARCHIVE" >/dev/null
sha256sum "$TOR_EDGE_CONFIG_ARCHIVE" >>"$MANIFEST_FILE"

TOR_EDGE_IDENTITIES_ARCHIVE="$CONFIG_DIR/tor-edge-identities-$TIMESTAMP.tar.gz"
echo "Creating tor-edge identity backup"
pct exec 201 -- bash -lc '
set -euo pipefail
mapfile -t identity_paths < <(find /var/lib/tor -maxdepth 2 -type f \( -name hostname -o -name hs_ed25519_secret_key -o -name hs_ed25519_public_key \) -printf "%P\n" | sort)
if (( ${#identity_paths[@]} == 0 )); then
  echo "No tor-edge identity files found" >&2
  exit 1
fi
tar -C /var/lib/tor -czf - "${identity_paths[@]}"
' >"$TOR_EDGE_IDENTITIES_ARCHIVE"

tar -tzf "$TOR_EDGE_IDENTITIES_ARCHIVE" >/dev/null
chmod 0600 "$TOR_EDGE_IDENTITIES_ARCHIVE"
sha256sum "$TOR_EDGE_IDENTITIES_ARCHIVE" >>"$MANIFEST_FILE"

BTC_NODE_CONFIG_ARCHIVE="$CONFIG_DIR/btc-node-config-$TIMESTAMP.tar.gz"
echo "Creating btc-node config backup"
pct exec 204 -- bash -lc '
set -euo pipefail
paths=(
  etc/bitcoin
  etc/default/prometheus-node-exporter
  etc/systemd/system/bitcoind.service
  etc/systemd/system/homelab-btc-firewall.service
  etc/systemd/system/bitcoin-node-metrics.service
  etc/systemd/system/bitcoin-node-metrics.timer
  etc/tor/torrc.d/bitcoin.conf
  usr/local/sbin/bitcoin-node-metrics.sh
  usr/local/sbin/homelab-btc-firewall.sh
)
for optional in var/lib/bitcoind/onion_v3_private_key var/lib/bitcoind/onion_v3_public_key var/lib/bitcoind/wallets; do
  if [[ -e "/${optional}" ]]; then
    paths+=("${optional}")
  fi
done
tar -C / -czf - "${paths[@]}"
' >"$BTC_NODE_CONFIG_ARCHIVE"

tar -tzf "$BTC_NODE_CONFIG_ARCHIVE" >/dev/null
chmod 0600 "$BTC_NODE_CONFIG_ARCHIVE"
sha256sum "$BTC_NODE_CONFIG_ARCHIVE" >>"$MANIFEST_FILE"

echo "Applying retention: keep the newest 3 backup runs"
mapfile -t existing_runs < <(find "$RUNS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
if (( ${#existing_runs[@]} > 3 )); then
  keep_from=$(( ${#existing_runs[@]} - 3 ))
  for run_name in "${existing_runs[@]:0:keep_from}"; do
    rm -rf -- "$RUNS_DIR/$run_name"
  done
fi

echo "DONE $TIMESTAMP"
