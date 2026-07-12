#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../../../..")"
COMPOSE="${PROJECT_ROOT}/docker-compose.yml"
STAGING="${PROJECT_ROOT}/secrets/hotwallet"

MNT="/mnt/usb"
LABEL="USB"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "[*] $*"
}

[[ $EUID -eq 0 ]] || die "als root ausführen"

set -a
source "${PROJECT_ROOT}/.env"
set +a

DEV="$(readlink -f /dev/disk/by-label/${LABEL} 2>/dev/null || true)"
[[ -n "$DEV" ]] || die "kein Device mit Label ${LABEL}"

mkdir -p "$MNT"
mountpoint -q "$MNT" || mount "$DEV" "$MNT"

cd "$MNT/psbt" || die "psbt-Ordner fehlt"

shopt -s nullglob
files=( *.txn )
shopt -u nullglob

[[ ${#files[@]} -eq 1 ]] || die "genau eine <id>.txn nötig"

FILE="${files[0]}"
base="$(basename "$FILE")"
psbt_id="${base%.txn}"

TX="$(tr -d '[:space:]' < "$FILE")"
[[ -n "$TX" ]] || die "leere TX"

cd /; umount "$MNT"; info "USB unmounted"

jq -n --arg id "$psbt_id" --arg tx "$TX" '{psbt_id:$id, tx:$tx}' \
  > "${STAGING}/ops_broadcast.json"

docker compose -f "$COMPOSE" exec -T \
  -e NATS_URL="nats://operator:${HOTWALLET_NATS_OPERATOR_PASS}@nats:4222" \
  middleware python -m src.com.nats_pub refill.broadcast.requested /run/ops_broadcast.json
  
info "broadcast.requested published (psbt_id=${psbt_id})"