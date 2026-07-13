#!/usr/bin/env bash
# Generates secrets/mosquitto.passwd with hashed passwords for Mosquitto.
# Reads plaintext passwords from .env (MQTT_*_PASSWORD vars).
# Run after changing any MQTT password; then redeploy the mosquitto service.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
OUTPUT_FILE="$ROOT_DIR/secrets/mosquitto.passwd"

# Users: "username:PASSWORD_ENV_VAR"
MQTT_USERS=(
    "homeassistant:MQTT_HOMEASSISTANT_PASSWORD"
    "zigbee2mqtt:MQTT_ZIGBEE2MQTT_PASSWORD"
    "esphome:MQTT_ESPHOME_PASSWORD"
    "readonly:MQTT_READONLY_PASSWORD"
)

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found. Copy .env.example to .env first." >&2
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

first=true
for entry in "${MQTT_USERS[@]}"; do
    IFS=':' read -r username var_name <<< "$entry"
    password="${!var_name:-}"
    if [[ -z "$password" ]]; then
        echo "ERROR: $var_name is not set in $ENV_FILE" >&2
        exit 1
    fi
    echo "Hashing password for user '$username'..."
    if [[ "$first" == true ]]; then
        nix-shell -p mosquitto --run \
            "mosquitto_passwd -c -b $(printf '%q' "$tmpfile") $(printf '%q' "$username") $(printf '%q' "$password")"
        first=false
    else
        nix-shell -p mosquitto --run \
            "mosquitto_passwd -b $(printf '%q' "$tmpfile") $(printf '%q' "$username") $(printf '%q' "$password")"
    fi
done

mkdir -p "$(dirname "$OUTPUT_FILE")"
cp "$tmpfile" "$OUTPUT_FILE"
chmod 600 "$OUTPUT_FILE"

echo "Done. Written to $OUTPUT_FILE"
