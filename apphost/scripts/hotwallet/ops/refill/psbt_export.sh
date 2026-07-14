#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../../../..")"        # apphost repo root
COMPOSE="${PROJECT_ROOT}/docker-compose.yml"
STAGING="${PROJECT_ROOT}/secrets/hotwallet"
# Ausgabeverzeichnis auf dem Apphost; die PSBT wird von hier per SSH abgeholt und
# per USB an die physische Cold-VM weitergereicht (kein USB-Mount auf dem Apphost).
OUT_DIR="${TRANSFER_DIR:-${STAGING}/transfer}/psbt"

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

PSBT_FILE="${STAGING}/refill.psbt"
[[ -s "$PSBT_FILE" ]] || die "keine gestagte PSBT ($PSBT_FILE)"

ID_FILE="${STAGING}/refill.psbt.id"
[[ -s "$ID_FILE"   ]] || die "keine psbt_id ($ID_FILE)"

psbt_id="$(cat "$ID_FILE")"

mkdir -p "$OUT_DIR"

shopt -s nullglob
existing=( "$OUT_DIR"/*.psbt "$OUT_DIR"/*.txn )
shopt -u nullglob

[[ ${#existing[@]} -eq 0 ]] || die "$OUT_DIR enthält bereits eine TX (Single-TX) – erst leeren"

cp -f "$PSBT_FILE" "$OUT_DIR/${psbt_id}.psbt"
info "Wrote $OUT_DIR/${psbt_id}.psbt"

echo '{}' > "${STAGING}/ops_export_done.json"

docker compose -f "$COMPOSE" exec -T \
  -e NATS_URL="nats://operator:${HOTWALLET_NATS_OPERATOR_PASS}@hotwallet-nats:4222" \
  hotwallet-middleware python -m src.com.nats_pub refill.export.done /run/ops_export_done.json
  
info "export.done published (psbt_id=${psbt_id})"