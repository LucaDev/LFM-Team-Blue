#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../../../..")"
COMPOSE="${PROJECT_ROOT}/docker-compose.yml"
STAGING="${PROJECT_ROOT}/secrets/hotwallet"

# Eingabeverzeichnis auf dem Apphost; die signierte TX wurde zuvor per SSH hierher
# kopiert (kein USB-Mount auf dem Apphost).
IN_DIR="${TRANSFER_DIR:-${STAGING}/transfer}/psbt"

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

[[ -d "$IN_DIR" ]] || die "Eingabeverzeichnis fehlt: $IN_DIR"

shopt -s nullglob
files=( "$IN_DIR"/*.txn )
shopt -u nullglob

[[ ${#files[@]} -eq 1 ]] || die "genau eine <id>.txn in $IN_DIR nötig"

FILE="${files[0]}"
base="$(basename "$FILE")"
psbt_id="${base%.txn}"

TX="$(tr -d '[:space:]' < "$FILE")"
[[ -n "$TX" ]] || die "leere TX"

jq -n --arg id "$psbt_id" --arg tx "$TX" '{psbt_id:$id, tx:$tx}' \
  > "${STAGING}/ops_broadcast.json"

docker compose -f "$COMPOSE" exec -T \
  -e NATS_URL="nats://operator:${HOTWALLET_NATS_OPERATOR_PASS}@hotwallet-nats:4222" \
  hotwallet-middleware python -m src.com.nats_pub refill.broadcast.requested /run/ops_broadcast.json
  
info "broadcast.requested published (psbt_id=${psbt_id})"