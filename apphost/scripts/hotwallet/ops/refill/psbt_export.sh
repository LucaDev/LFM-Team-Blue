#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../../../..")"        # apphost repo root
COMPOSE="${PROJECT_ROOT}/docker-compose.yml"
STAGING="${PROJECT_ROOT}/secrets/hotwallet"
MNT="/mnt/usb"; LABEL="USB"

die() {
  echo "ERROR: $*" >&2
  exit 1+
  }
info() {
  echo "[*] $*"
}

[[ $EUID -eq 0 ]] || die "als root ausführen"
set -a
source "${PROJECT_ROOT}/.env"
set +a

PSBT_FILE="${STAGING}/refill.psbt"
[[ -s "$PSBT_FILE" ]] || die "keine gestagte PSBT ($PSBT_FILE)"

ID_FILE="${STAGING}/refill.psbt.id"
[[ -s "$ID_FILE"   ]] || die "keine psbt_id ($ID_FILE)"

psbt_id="$(cat "$ID_FILE")"

DEV="$(readlink -f /dev/disk/by-label/${LABEL} 2>/dev/null || true)"
[[ -n "$DEV" ]] || die "kein Device mit Label ${LABEL}"

mkdir -p "$MNT"
mountpoint -q "$MNT" || mount "$DEV" "$MNT"
mkdir -p "$MNT/psbt"

shopt -s nullglob
existing=( "$MNT/psbt"/*.psbt "$MNT/psbt"/*.txn )
shopt -u nullglob

[[ ${#existing[@]} -eq 0 ]] || die "USB hat bereits eine TX (Single-TX)"

cp -f "$PSBT_FILE" "$MNT/psbt/${psbt_id}.psbt"
sync
info "Wrote ${psbt_id}.psbt"

umount "$MNT"
info "USB unmounted"

echo '{}' > "${STAGING}/ops_export_done.json"

docker compose -f "$COMPOSE" exec -T \
  -e NATS_URL="nats://operator:${HOTWALLET_NATS_OPERATOR_PASS}@nats:4222" \
  middleware python -m src.com.nats_pub refill.export.done /run/ops_export_done.json
  
info "export.done published (psbt_id=${psbt_id})"