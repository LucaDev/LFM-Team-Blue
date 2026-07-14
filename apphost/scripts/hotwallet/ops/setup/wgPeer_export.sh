#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../../../..")"

# Ausgabeverzeichnis auf dem Apphost. Die exportierte Datei wird von hier per SSH
# abgeholt und per USB an die physische Signer-VM weitergereicht.
TRANSFER_DIR="${TRANSFER_DIR:-${PROJECT_ROOT}/secrets/hotwallet/transfer}"

#Wenn noch nicht erstellt
PRIVATE_KEY=/etc/wireguard/private.key
PUBLIC_KEY=/etc/wireguard/public.key

if [[ ! -f "$PRIVATE_KEY" ]]; then
    echo "Generating local WireGuard keypair..."

    umask 077
    wg genkey | tee "$PRIVATE_KEY" | wg pubkey > "$PUBLIC_KEY"

    chmod 600 "$PRIVATE_KEY"
    chmod 644 "$PUBLIC_KEY"
fi

mkdir -p "$TRANSFER_DIR/communication/wireguard"



WG_PORT="51820"


if [[ -z "${SIGNER_ENDPOINT_IP:-}" ]]; then
  SIGNER_ENDPOINT_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
fi


SIGNER_IP="10.10.0.2/32"
WALLET_IP="10.10.0.1/32"

SIGNER_PUB_KEY="$(cat "$PUBLIC_KEY")"

WIREGUARD_JSON="$TRANSFER_DIR/communication/wireguard/wireguard.wallet.json"

cat > "$WIREGUARD_JSON" <<EOF
{
  "wallet_public_key": "$SIGNER_PUB_KEY",
  "signer_ip": "$SIGNER_IP",
  "wallet_ip": "$WALLET_IP",
  "port": $WG_PORT,
  "endpoint": "${SIGNER_ENDPOINT_IP}:${WG_PORT}",
  "allowed_ips_signer": "$WALLET_IP/32",
  "allowed_ips_wallet": "$SIGNER_IP/32"
}
EOF

chmod 644 "$WIREGUARD_JSON"

echo "WireGuard contract exported:"
echo "  $WIREGUARD_JSON"

echo "done"