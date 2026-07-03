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
    echo "MW_NATS_PASS=n$(openssl rand -hex 24)"
    echo "TXB_NATS_PASS=n$(openssl rand -hex 24)"
    echo "OPERATOR_NATS_PASS=n$(openssl rand -hex 24)"
    echo "SETUP_NATS_PASS=n$(openssl rand -hex 24)"
    echo "OPERATOR_TOKEN=$(openssl rand -hex 24)"
    echo "NTFY_TOKEN=$(openssl rand -hex 24)"
    echo "POSTGRES_USER=signer"
    echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
    echo "POSTGRES_DB=btc"
    echo "MW_DB_USER=mw_app"
    echo "MW_DB_PASSWORD=$(openssl rand -hex 24)"
    echo "BTC_RPC_USER_MW=${MW_USER}"
    echo "BTC_RPC_PASS_MW=${MW_PASS}"
    echo "BTC_RPC_USER_TXB=${TXB_USER}"
    echo "BTC_RPC_PASS_TXB=${TXB_PASS}"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  rm -f "$RPCAUTH_FILE"     #damit neue rpcauth.conf erzeugt wird (siehe unten)
  echo "[*] .env erzeugt"
fi


if [[ -f "$RPCAUTH_FILE" ]]; then
  echo "[*] rpcauth.conf existiert bereits – bleibt unverändert"
else
  set -a; . "$ENV_FILE"; set +a          # BTC_RPC_USER_*/PASS_* laden
  make_rpcauth() {                        # $1=user  $2=klartext-pass  ->  rpcauth-Zeile
    local user="$1" pass="$2" salt hmac
    salt="$(openssl rand -hex 16)"
    hmac="$(printf '%s' "$pass" | openssl dgst -sha256 -hmac "$salt" | sed 's/^.* //')"
    printf 'rpcauth=%s:%s$%s\n' "$user" "$salt" "$hmac"
  }
  {
    make_rpcauth "$BTC_RPC_USER_MW"  "$BTC_RPC_PASS_MW"
    make_rpcauth "$BTC_RPC_USER_TXB" "$BTC_RPC_PASS_TXB"
  } > "$RPCAUTH_FILE"
  chmod 644 "$RPCAUTH_FILE"
  echo "[*] rpcauth.conf erzeugt"
fi

#Verzeichnis-Eigentümer für non-root Container
mkdir -p "${PROJECT_ROOT}/middleware_data/wallets" \
         "${PROJECT_ROOT}/middleware_data/secrets"
chown -R "${CONTAINER_UID}:${CONTAINER_GID}" "${PROJECT_ROOT}/middleware_data"
echo "[*] middleware_data -> ${CONTAINER_UID}:${CONTAINER_GID}"