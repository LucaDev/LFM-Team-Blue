#!/usr/bin/env bash
set -euo pipefail

PRIVATE_KEY=/var/lib/wireguard/private.key
WG_PORT="51820"

if [[ -z "${SIGNER_ENDPOINT_IP:-}" ]]; then
  SIGNER_ENDPOINT_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
fi

SIGNER_IP="10.10.0.2/32"
WALLET_IP="10.10.0.1/32"

SIGNER_PUB_KEY="$(wg pubkey < $PRIVATE_KEY)"
echo " \
{ \
  \"wallet_public_key\": \"$SIGNER_PUB_KEY\", \
  \"signer_ip\": \"$SIGNER_IP\", \
  \"wallet_ip\": \"$WALLET_IP\", \
  \"port\": $WG_PORT, \
  \"endpoint\": \"${SIGNER_ENDPOINT_IP}:${WG_PORT}\", \
  \"allowed_ips_signer\": \"$WALLET_IP/32\", \
  \"allowed_ips_wallet\": \"$SIGNER_IP/32\" \
}"


echo "done"
