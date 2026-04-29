#!/usr/bin/env bash
set -euo pipefail

CFG="/etc/nixos/configuration.nix"


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


nixos-rebuild build 

echo "Build done:"

RESULT="$(readlink -f ./result)"

echo "Applying now..."
"$Result/bin/switch-to-configuration" switch

echo "Airgap applied."