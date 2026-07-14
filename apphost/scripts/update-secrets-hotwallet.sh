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

# openssl ist nicht auf jedem System vorinstalliert (z.B. Live-ISO beim Ersteinrichten
# via nixos/install.sh), daher via nix-shell statt direktem Aufruf.
_openssl() { nix-shell -p openssl --run "openssl $*"; }

rpcauth_line() {
    local user="$1" password="$2" salt hmac
    salt="$(_openssl rand -hex 16)"
    hmac="$(printf '%s' "$password" | _openssl dgst -sha256 -hmac "$salt" | sed 's/^.* //')"
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

# hotwallet-btc-core läuft im Container als UID 1000, aber Docker's userns-remap
# (dockremap, siehe nixos/modules/docker.nix) verschiebt Container-UIDs auf dem Host
# um einen festen Offset
if [[ "$(id -u)" -eq 0 ]]; then
    # Beim allerersten Lauf aus nixos/install.sh läuft dieses Skript auf der Live-ISO
    # gegen das noch nicht gebootete Zielsystem unter /mnt (ROOT_DIR=/mnt/opt/monorepo/apphost);
    # "dockremap" steht dann nur in /mnt/etc/subuid, nicht im /etc/subuid der ISO selbst.
    # Bei jedem späteren manuellen Lauf auf dem gebooteten System liegt ROOT_DIR nicht
    # unter /mnt, dann ist /etc/subuid direkt richtig.
    SUBUID_FILE="/etc/subuid"
    [[ "$ROOT_DIR" == /mnt/* ]] && SUBUID_FILE="/mnt/etc/subuid"
    REMAP_BASE="$(awk -F: '$1=="dockremap"{print $2}' "$SUBUID_FILE" 2>/dev/null || true)"
    if [[ -n "$REMAP_BASE" ]]; then
        chown "$((REMAP_BASE + 1000)):$((REMAP_BASE + 1000))" "$OUTPUT_FILE"
        echo "  -> Ownership $((REMAP_BASE + 1000)):$((REMAP_BASE + 1000)) gesetzt (userns-remap-UID für Container-UID 1000)"
    else
        echo "WARNING: dockremap nicht in /etc/subuid gefunden – Ownership nicht gesetzt (userns-remap aktiv?)" >&2
    fi
fi

echo "Done. Written to $OUTPUT_FILE"
