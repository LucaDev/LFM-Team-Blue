#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../..")"          # Hot-Wallet
COMPOSE="${PROJECT_ROOT}/docker-compose.yaml"; STAGING="${PROJECT_ROOT}/middleware_data"
PSBT_DIR="${1:-${PSBT_DIR:-$SCRIPT_DIR}}"
die(){ echo "ERROR: $*" >&2; exit 1; }; info(){ echo "[*] $*"; }
set -a; source "${PROJECT_ROOT}/.env"; set +a

shopt -s nullglob; files=( "$PSBT_DIR"/*.psbt ); shopt -u nullglob
[[ ${#files[@]} -eq 1 ]] || die "genau eine .psbt in ${PSBT_DIR} nötig"
FILE="${files[0]}"; info "Datei: $FILE"

MAGIC=$(head -c 5 "$FILE" | od -An -tx1 | tr -d ' \n')
if [[ "$MAGIC" == "70736274ff" ]]; then
  PSBT_B64=$(base64 -w0 "$FILE"); SHA256=$(sha256sum "$FILE" | awk '{print $1}')
else
  PSBT_B64=$(tr -d '[:space:]' < "$FILE"); SHA256=$(printf '%s' "$PSBT_B64" | base64 -d | sha256sum | awk '{print $1}')
fi

jq -n --arg psbt "$PSBT_B64" --arg sha "$SHA256" '{psbt:$psbt, sha256:$sha}' \
  > "${STAGING}/ops_submit.json"
docker compose -f "$COMPOSE" exec -T \
  -e NATS_URL="nats://operator:${OPERATOR_NATS_PASS}@nats:4222" \
  middleware python -m src.com.nats_pub psbt.submit.requested /run/ops_submit.json
info "psbt.submit.requested published"