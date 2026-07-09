#!/usr/bin/env bash
set -euo pipefail

CLI=/opt/bitcoin-core/current/bin/bitcoin-cli
CONF=/etc/bitcoin/bitcoin.conf
DATADIR=/var/lib/bitcoind
TEXTFILE_DIR=/var/lib/prometheus/node-exporter-textfile
OUTPUT_FILE="$TEXTFILE_DIR/bitcoin_node.prom"
TMP_FILE="$(mktemp "$TEXTFILE_DIR/bitcoin_node.prom.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

install -d -m 0755 "$TEXTFILE_DIR"

timestamp="$(date +%s)"
blockchain_info="$($CLI -conf="$CONF" -datadir="$DATADIR" getblockchaininfo 2>/dev/null || true)"
network_info="$($CLI -conf="$CONF" -datadir="$DATADIR" getnetworkinfo 2>/dev/null || true)"
mempool_info="$($CLI -conf="$CONF" -datadir="$DATADIR" getmempoolinfo 2>/dev/null || true)"

bool_to_num() {
  if [[ "$1" == "true" ]]; then
    echo 1
  else
    echo 0
  fi
}

{
  echo '# HELP homelab_bitcoin_rpc_up Whether the local Bitcoin RPC responded successfully.'
  echo '# TYPE homelab_bitcoin_rpc_up gauge'
  echo '# HELP homelab_bitcoin_scrape_timestamp_seconds Unix timestamp of the last local Bitcoin metrics run.'
  echo '# TYPE homelab_bitcoin_scrape_timestamp_seconds gauge'
  printf 'homelab_bitcoin_scrape_timestamp_seconds %s\n' "$timestamp"

  if [[ -n "$blockchain_info" && -n "$network_info" && -n "$mempool_info" ]]; then
    blocks="$(jq -r '.blocks // 0' <<<"$blockchain_info")"
    headers="$(jq -r '.headers // 0' <<<"$blockchain_info")"
    progress="$(jq -r '.verificationprogress // 0' <<<"$blockchain_info")"
    ibd="$(jq -r '.initialblockdownload // false' <<<"$blockchain_info")"
    pruned="$(jq -r '.pruned // false' <<<"$blockchain_info")"
    size_on_disk="$(jq -r '.size_on_disk // 0' <<<"$blockchain_info")"
    peers="$(jq -r '.connections // 0' <<<"$network_info")"
    subversion="$(jq -r '.subversion // ""' <<<"$network_info")"
    onion_count="$(jq -r '[.localaddresses[]? | select((.network // "") == "onion" or ((.address // "") | endswith(".onion")))] | length' <<<"$network_info")"
    mempool_bytes="$(jq -r '.bytes // 0' <<<"$mempool_info")"
    mempool_size="$(jq -r '.size // 0' <<<"$mempool_info")"

    echo 'homelab_bitcoin_rpc_up 1'
    printf 'homelab_bitcoin_blocks %s\n' "$blocks"
    printf 'homelab_bitcoin_headers %s\n' "$headers"
    printf 'homelab_bitcoin_verification_progress %.12f\n' "$progress"
    printf 'homelab_bitcoin_initialblockdownload %s\n' "$(bool_to_num "$ibd")"
    printf 'homelab_bitcoin_pruned %s\n' "$(bool_to_num "$pruned")"
    printf 'homelab_bitcoin_size_on_disk_bytes %s\n' "$size_on_disk"
    printf 'homelab_bitcoin_peers %s\n' "$peers"
    printf 'homelab_bitcoin_onion_service_advertised %s\n' "$([[ "$onion_count" -gt 0 ]] && echo 1 || echo 0)"
    printf 'homelab_bitcoin_mempool_bytes %s\n' "$mempool_bytes"
    printf 'homelab_bitcoin_mempool_transactions %s\n' "$mempool_size"
    printf 'homelab_bitcoin_version_info{version="%s"} 1\n' "$subversion"
  else
    echo 'homelab_bitcoin_rpc_up 0'
  fi
} >"$TMP_FILE"

chmod 0644 "$TMP_FILE"
mv "$TMP_FILE" "$OUTPUT_FILE"
