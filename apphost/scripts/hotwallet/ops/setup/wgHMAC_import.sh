#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../../../..")"

SECRETS_DIR="${PROJECT_ROOT}/secrets/hotwallet/secrets"
ENV_RUNTIME="${PROJECT_ROOT}/secrets/hotwallet/secrets/env.runtime"

SIGNER_IP="10.10.0.2"
SIGNER_URL="http://${SIGNER_IP}:8080"

#########################################
#HMAC
if [[ -f "./signer-hmac.secret" ]]; then
    cp "./signer-hmac.secret" \
       "$SECRETS_DIR/signer-hmac.secret"
    chmod 600 "$SECRETS_DIR/signer-hmac.secret"
    # hotwallet-middleware läuft im Container als UID 1000, aber Docker's userns-remap
    # (dockremap, siehe nixos/modules/docker.nix) verschiebt Container-UIDs auf dem Host
    # um einen festen Offset
    if [[ "$(id -u)" -eq 0 ]]; then
        REMAP_BASE="$(awk -F: '$1=="dockremap"{print $2}' /etc/subuid 2>/dev/null || true)"
        if [[ -n "$REMAP_BASE" ]]; then
            chown "$((REMAP_BASE + 1000)):$((REMAP_BASE + 1000))" "$SECRETS_DIR/signer-hmac.secret"
        else
            echo "WARNING: dockremap nicht in /etc/subuid gefunden – Ownership nicht gesetzt (userns-remap aktiv?)" >&2
        fi
    fi
    echo "Imported: signer-hmac.secret"

    HMAC_SECRET=$(cat "$SECRETS_DIR/signer-hmac.secret")

    cat > "$ENV_RUNTIME" <<EOF
    SIGNER_URL=${SIGNER_URL}
    SIGNER_HMAC_SECRET=${HMAC_SECRET}
EOF

    chmod 600 "$ENV_RUNTIME"
    echo "Generated: env.runtime"
    echo ""
    echo "Import complete"
    echo "Signer URL: ${SIGNER_URL}"
else
    echo "Error: signer-hmac.secret not found in current directory. Please provide the secret file to import."
fi
