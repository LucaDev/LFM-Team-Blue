#!/usr/bin/env bash
set -euo pipefail

CFG="/etc/nixos/configuration.nix"
OUT="/root/airgap-result"

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }
[ -f "$CFG" ] || { echo "ERROR: $CFG not found" >&2; exit 1; }

# checken, ob bereits true
if grep -Eq '^\s*airgap\.enable\s*=\s*true\s*;' "$CFG"; then
  echo "airgap.enable is already true (in $CFG). Nothing to do."
  exit 0
fi


# ersetzen
sed -i -E 's/^\s*airgap\.enable\s*=\s*(true|false)\s*;/  airgap.enable = true;/' "$CFG"
echo "Set airgap.enable=true"


rm -f "$OUT"
nixos-rebuild build --out-link "$OUT"

echo "Build done: $OUT"

echo "Applying now..."
"$OUT/bin/switch-to-configuration" switch

echo "Airgap applied."