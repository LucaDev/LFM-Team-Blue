#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../../../..")"

# NATS-Credentials aus .env holen (HOTWALLET_NATS_SETUP_PASS)
set -a; source "$PROJECT_ROOT/.env"; set +a

WALLET_DIR="${PROJECT_ROOT}/secrets/hotwallet/wallets"

# Verzeichnis auf dem Apphost, in das die Wallet-Dateien zuvor per SSH kopiert
# wurden (kein USB-Mount auf dem Apphost).
TRANSFER_DIR="${TRANSFER_DIR:-${PROJECT_ROOT}/secrets/hotwallet/transfer}"

patch_metadata() {
  local meta_file="$1"
  local wallet_type="$2"
  local wallet_dir="$3"

  local xpub_file="$wallet_dir/xpub.txt"

  if [[ ! -f "$xpub_file" ]]; then
    echo "ERROR: missing xpub.txt in $wallet_dir" >&2
    return 1
  fi

  local xpub
  xpub=$(cat "$xpub_file")


  local tmp
  tmp=$(mktemp)

  jq \
    --arg wallet_type "$wallet_type" \
    --arg xpub "$xpub" \
    '
    .wallet_type = ($wallet_type)
    | .xpub = (if $xpub == "" then null else $xpub end)
    ' "$meta_file" > "$tmp"

  mv "$tmp" "$meta_file"
}

echo "Writing to host docker mount: $PROJECT_ROOT/secrets/hotwallet"

echo "=== Import Hot/Cold Signer ==="

mkdir -p "$WALLET_DIR"

echo "Importing wallets from $TRANSFER_DIR ..."

FOUND=0

for WALLET_TYPE_DIR in "$TRANSFER_DIR/wallet"/*/
do
    [[ -d "$WALLET_TYPE_DIR" ]] || continue

    WALLET_TYPE=$(basename "$WALLET_TYPE_DIR")

    # nur hot/cold erlauben (optional harte Validierung)
    if [[ "$WALLET_TYPE" != "hot" && "$WALLET_TYPE" != "cold" ]]; then
        echo "Skipping unknown wallet type: $WALLET_TYPE"
        continue
    fi

    WALLET_META="$WALLET_TYPE_DIR/metadata.json"

    if [[ "$WALLET_TYPE" == "hot" ]]; then

        if [[ ! -f "$WALLET_META" ]]; then
            echo "Skipping hot"
            continue
        fi

        FOUND=1

        patch_metadata "$WALLET_META" "$WALLET_TYPE" "$WALLET_TYPE_DIR"

    elif [[ "$WALLET_TYPE" == "cold" ]]; then

        COLD_SIGNER="$WALLET_TYPE_DIR/cold-signer.wsh"

        if [[ ! -f "$COLD_SIGNER" ]]; then
            echo "Skipping cold"
            continue
        fi

        FOUND=1
        WALLET_META=$(mktemp)

        jq -n \
          --arg wallet_type "cold" \
          --arg wallet_name "cold-multi" \
          --arg desc "$(tail -n 1 "$COLD_SIGNER")" \
          --arg network "regtest" \
          '
          {
            wallet_type: $wallet_type,
            wallet_name: $wallet_name,
            xpub: "",
            descriptor: $desc,
            network: $network,
          }
          ' > "$WALLET_META"

    fi

    echo ""
    echo "----------------------------------"
    echo "Wallet type: $WALLET_TYPE"
    echo "----------------------------------"

    mkdir -p "$WALLET_DIR/$WALLET_TYPE"

    cp "$WALLET_TYPE_DIR/"* "$WALLET_DIR/$WALLET_TYPE/"
    find "$WALLET_DIR/$WALLET_TYPE" -type f -exec chmod 644 {} \;
    
        cp -f "$WALLET_META" "$WALLET_DIR/$WALLET_TYPE/metadata.json"

    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T \
        -e NATS_URL="nats://setup:${HOTWALLET_NATS_SETUP_PASS}@hotwallet-nats:4222" \
        hotwallet-middleware python -m src.com.nats_pub \
        wallet.import.requested "/run/wallets/$WALLET_TYPE/metadata.json"
    then
        echo "OK: $WALLET_TYPE import gestartet"
    else
        echo "FEHLER: NATS-Publish fehlgeschlagen (läuft der Stack?)"
    fi
done

if [[ "$FOUND" -eq 0 ]]; then
    echo "WARNING: no wallets found"
fi

echo ""
echo "Import complete"