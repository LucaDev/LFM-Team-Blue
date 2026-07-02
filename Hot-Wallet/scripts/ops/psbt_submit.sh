#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../../..")"

API_BASE="${API_BASE:-http://localhost:8080}"
PSBT_DIR="${1:-${PSBT_DIR:-$SCRIPT_DIR}}"   # Standard: dieses Verzeichnis (Sparrow legt die .psbt hier ab)

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "[*] $*"; }

# .env laden (OPERATOR_TOKEN)
set -a; source "${PROJECT_ROOT}/.env"; set +a
[[ -n "${OPERATOR_TOKEN:-}" ]] || die "OPERATOR_TOKEN fehlt (in .env setzen)"

# Genau eine .psbt (Single-TX-Regel)
shopt -s nullglob
files=( "$PSBT_DIR"/*.psbt )
shopt -u nullglob
[[ ${#files[@]} -ne 0 ]] || die "Keine .psbt in ${PSBT_DIR}"
[[ ${#files[@]} -eq 1 ]] || die "Mehr als eine .psbt gefunden (unsafe): ${files[*]}"
FILE="${files[0]}"
info "Datei: $FILE"

# Binär (Sparrow "Save Transaction") vs. Base64-Text erkennen
MAGIC=$(head -c 5 "$FILE" | od -An -tx1 | tr -d ' \n')
if [[ "$MAGIC" == "70736274ff" ]]; then
    PSBT_B64=$(base64 -w0 "$FILE")
    SHA256=$(sha256sum "$FILE" | awk '{print $1}')
else
    PSBT_B64=$(tr -d '[:space:]' < "$FILE")
    SHA256=$(printf '%s' "$PSBT_B64" | base64 -d | sha256sum | awk '{print $1}')
fi

# SHA256 über die DEKODIERTEN Bytes – exakt so prüft der Signer (Hot-KeyHolder-Doku 1.3)
BODY=$(jq -n --arg psbt "$PSBT_B64" --arg sha "$SHA256" '{psbt: $psbt, sha256: $sha}')

resp="$(curl -fsSL -X POST \
  -H "Content-Type: application/json" \
  -H "X-Operator-Token: ${OPERATOR_TOKEN}" \
  --data "$BODY" \
  "${API_BASE}/api/v1/request/psbt")" || die "Submit fehlgeschlagen"

echo "$resp" | jq .
info "PSBT eingereicht"