#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../../../..")"
COMPOSE="${PROJECT_ROOT}/docker-compose.yml"
EXT_DIR="${PROJECT_ROOT}/secrets/hotwallet/wallets/ext"

# .env laden (HOTWALLET_NATS_SETUP_PASS)
set -a; source "${PROJECT_ROOT}/.env"; set +a

mkdir -p "$EXT_DIR"
shopt -s nullglob

SRC_DIR="${1:-.}"
mapfile -t METAS < <(ls "${SRC_DIR}"/*.meta.json 2>/dev/null)

echo "[*] Suche *.meta.json in: $(realpath "$SRC_DIR")"
if (( ${#METAS[@]} == 0 )); then
  echo "[!] Keine *.meta.json gefunden – nichts zu tun."
  exit 0
fi
echo "[*] ${#METAS[@]} Datei(en) gefunden."

for META_FILE in "${METAS[@]}"; do
  echo "Processing: $META_FILE"

  #Werte aus meta.json lesen
  WALLET_NAME=$(jq -r '.wallet_name' "$META_FILE")
  NETWORK=$(jq -r '.network' "$META_FILE")
  XPUB=$(jq -r '.xpub // ""' "$META_FILE")
  DESCRIPTOR=$(jq -r '.descriptor // ""' "$META_FILE")
  DERIVATION_PATH=$(jq -r '.derivation_path // ""' "$META_FILE")
  MASTER_FINGERPRINT=$(jq -r '.master_fingerprint // ""' "$META_FILE")

  # Payload bauen
  # Payload ins (read-only in den Container gemountete) Volume schreiben
  OUT="${EXT_DIR}/${WALLET_NAME}.json"
  jq -n \
    --arg wallet_type "ext" \
    --arg wallet_name "$WALLET_NAME" \
    --arg network "$NETWORK" \
    --arg xpub "$XPUB" \
    --arg descriptor "$DESCRIPTOR" \
    --arg derivation_path "$DERIVATION_PATH" \
    --arg master_fingerprint "$MASTER_FINGERPRINT" \
    '{
      wallet_type: $wallet_type,
      wallet_name: $wallet_name,
      network: $network,
      xpub: $xpub,
      descriptor: $descriptor,
      derivation_path: $derivation_path,
      master_fingerprint: $master_fingerprint
    }' > "$OUT"

 

  if docker compose -f "$COMPOSE" exec -T \
      -e NATS_URL="nats://setup:${HOTWALLET_NATS_SETUP_PASS}@nats:4222" \
      middleware python -m src.com.nats_pub \
      wallet.import.requested "/run/wallets/ext/${WALLET_NAME}.json"
  then
      echo "OK: ext-Wallet '${WALLET_NAME}' import angestoßen"
  else
      echo "FEHLER: NATS-Publish für '${WALLET_NAME}' fehlgeschlagen (läuft der Stack?)"
  fi

done