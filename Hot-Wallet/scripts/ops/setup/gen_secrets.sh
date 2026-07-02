#!/usr/bin/env bash
set -euo pipefail
ENV_FILE="$(cd "$(dirname "$0")/../../.." && pwd)/.env"   # -> Hot-Wallet/.env
if [[ -f "$ENV_FILE" ]]; then
  echo "[*] .env existiert bereits – nichts zu tun"; exit 0
fi
{
  echo "MW_NATS_PASS=$(openssl rand -hex 24)"
  echo "TXB_NATS_PASS=$(openssl rand -hex 24)"
  echo "OPERATOR_NATS_PASS=$(openssl rand -hex 24)"
  echo "SETUP_NATS_PASS=$(openssl rand -hex 24)"
  echo "OPERATOR_TOKEN=$(openssl rand -hex 24)"
  echo "POSTGRES_USER=signer"
  echo "POSTGRES_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -hex 24)"
  echo "POSTGRES_DB=btc"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"
echo "[*] .env erzeugt"