#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
RPCAUTH_FILE="${PROJECT_ROOT}/services/btc-core/src/rpcauth.conf"

CONTAINER_UID=1000
CONTAINER_GID=1000


gen_rpcauth() {
  local user="$1" pass salt hmac
  pass="$(openssl rand -hex 24)"
  salt="$(openssl rand -hex 16)"
  hmac="$(printf '%s' "$pass" | openssl dgst -sha256 -hmac "$salt" | sed 's/^.* //')"
  printf '%s|%s|%s:%s$%s' "$user" "$pass" "$user" "$salt" "$hmac"
}

if [[ -f "$ENV_FILE" ]]; then
  echo "[*] .env existiert bereits – Secrets bleiben unverändert"
else
  IFS='|' read -r MW_USER  MW_PASS  MW_AUTH  <<< "$(gen_rpcauth middleware)"
  IFS='|' read -r TXB_USER TXB_PASS TXB_AUTH <<< "$(gen_rpcauth txbuilder)"

  {
    echo "MW_NATS_PASS=$(openssl rand -hex 24)"
    echo "TXB_NATS_PASS=$(openssl rand -hex 24)"
    echo "OPERATOR_NATS_PASS=$(openssl rand -hex 24)"
    echo "SETUP_NATS_PASS=$(openssl rand -hex 24)"
    echo "OPERATOR_TOKEN=$(openssl rand -hex 24)"
    echo "NTFY_TOKEN=$(openssl rand -hex 24)"
    echo "POSTGRES_USER=signer"
    echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
    echo "POSTGRES_DB=btc"
    echo "MW_DB_USER=mw_app"
    echo "MW_DB_PASSWORD=$(openssl rand -hex 24)"
    # Nur Klartext-Client-Creds (kein '$') in die .env:
    echo "BTC_RPC_USER_MW=${MW_USER}"
    echo "BTC_RPC_PASS_MW=${MW_PASS}"
    echo "BTC_RPC_USER_TXB=${TXB_USER}"
    echo "BTC_RPC_PASS_TXB=${TXB_PASS}"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"

  #rpcauth-Hashes nicht in .env(wegen '$')
  {
    echo "rpcauth=${MW_AUTH}"
    echo "rpcauth=${TXB_AUTH}"
  } > "$RPCAUTH_FILE"
  chmod 600 "$RPCAUTH_FILE"
  echo "[*] .env + rpcauth.conf erzeugt"
fi

#Verzeichnis-Eigentümer für non-root Container
mkdir -p "${PROJECT_ROOT}/middleware_data/wallets" \
         "${PROJECT_ROOT}/middleware_data/secrets"
chown -R "${CONTAINER_UID}:${CONTAINER_GID}" "${PROJECT_ROOT}/middleware_data"
echo "[*] middleware_data -> ${CONTAINER_UID}:${CONTAINER_GID}"