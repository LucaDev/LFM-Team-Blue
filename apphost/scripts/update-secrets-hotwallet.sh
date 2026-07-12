#!/usr/bin/env bash
# Generates services/hotwallet/btc-core/src/rpcauth.conf from the plaintext
# RPC passwords in .env (HOTWALLET_RPC_PASS_MW, HOTWALLET_RPC_PASS_TXB).
# Run after changing either password; then redeploy hotwallet-btc-core.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
OUTPUT_FILE="$ROOT_DIR/services/hotwallet/btc-core/src/rpcauth.conf"

# RPC users: "username:PASSWORD_ENV_VAR" – Benutzernamen sind fest im
# Middleware-/tx-builder-Environment verdrahtet (compose/finance/hotwallet.yml),
# hier NICHT ändern ohne die dortigen BTC_CORE_RPC_USER-Werte anzupassen.
RPC_USERS=(
    "middleware:HOTWALLET_RPC_PASS_MW"
    "txbuilder:HOTWALLET_RPC_PASS_TXB"
)

# ---------------------------------------------------------------------------

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found. Copy .env.example to .env first." >&2
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

rpcauth_line() {
    local user="$1" password="$2" salt hmac
    salt="$(openssl rand -hex 16)"
    hmac="$(printf '%s' "$password" | openssl dgst -sha256 -hmac "$salt" | sed 's/^.* //')"
    printf 'rpcauth=%s:%s$%s\n' "$user" "$salt" "$hmac"
}

mkdir -p "$(dirname "$OUTPUT_FILE")"
: > "$OUTPUT_FILE"

for entry in "${RPC_USERS[@]}"; do
    IFS=':' read -r username var_name <<< "$entry"
    password="${!var_name:-}"
    if [[ -z "$password" ]]; then
        echo "ERROR: $var_name is not set in $ENV_FILE" >&2
        exit 1
    fi
    echo "Generating rpcauth entry for '$username'..."
    rpcauth_line "$username" "$password" >> "$OUTPUT_FILE"
done

chmod 600 "$OUTPUT_FILE"
echo "Done. Written to $OUTPUT_FILE"
