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
# mosquitto_passwd -c refuses to write to a file that already exists (see below),
# aber mktemp legt die Datei zur Reservierung des Namens bereits an.
rm -f "$tmpfile"

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

# mosquitto läuft im Container als UID 1883 (user: "1883:1883" in compose/home/mosquitto.yml),
# aber Docker's userns-remap (dockremap, siehe nixos/modules/docker.nix) verschiebt
# Container-UIDs auf dem Host um einen festen Offset
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
        chown "$((REMAP_BASE + 1883)):$((REMAP_BASE + 1883))" "$OUTPUT_FILE"
        echo "  -> Ownership $((REMAP_BASE + 1883)):$((REMAP_BASE + 1883)) gesetzt (userns-remap-UID für Container-UID 1883)"
    else
        echo "WARNING: dockremap nicht in /etc/subuid gefunden – Ownership nicht gesetzt (userns-remap aktiv?)" >&2
    fi
fi

echo "Done. Written to $OUTPUT_FILE"
