#!/usr/bin/env bash
set -euo pipefail

BASE="http://localhost:8080/api/v1/importWallet"

shopt -s nullglob

for META_FILE in ./*.meta.json; do
  echo "Processing: $META_FILE"

  #Werte aus meta.json lesen
  WALLET_NAME=$(jq -r '.wallet_name' "$META_FILE")
  NETWORK=$(jq -r '.network' "$META_FILE")
  XPUB=$(jq -r '.xpub // ""' "$META_FILE")
  DESCRIPTOR=$(jq -r '.descriptor // ""' "$META_FILE")
  DERIVATION_PATH=$(jq -r '.derivation_path // ""' "$META_FILE")
  MASTER_FINGERPRINT=$(jq -r '.master_fingerprint // ""' "$META_FILE")

  # Payload bauen
  PAYLOAD=$(jq -n \
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
    }'
  )

  # Request senden
  RESPONSE=$(curl -s -X POST "$BASE" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  echo "$RESPONSE" | jq .

done