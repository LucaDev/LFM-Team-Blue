#!/usr/bin/env bash
set -euo pipefail

CFG="/etc/nixos/configuration.nix"
FLAKE_DIR="/etc/nixos"
TARGET="cold"

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }
[ -f "$CFG" ] || { echo "ERROR: $CFG not found" >&2; exit 1; }

# already enabled?
if grep -Eq '^\s*airgap\.enable\s*=\s*true\s*;' "$CFG"; then
  echo "airgap.enable is already true (in $CFG). Nothing to do."
  exit 0
fi

# replace existing setting, if present
if grep -Eq '^\s*airgap\.enable\s*=' "$CFG"; then
  sed -i -E 's/^\s*airgap\.enable\s*=\s*(true|false)\s*;/  airgap.enable = true;/' "$CFG"
  echo "Set airgap.enable=true"
else
  echo "ERROR: airgap.enable not found in $CFG."
  echo "Add 'airgap.enable = false;' once in the right module scope, then rerun."
  exit 1
fi

echo "Building (flake: ${FLAKE_DIR}#${TARGET})..."
OUT_LINK="$(mktemp -d)/result"

nixos-rebuild build \
  --flake "path:${FLAKE_DIR}#${TARGET}" \
  --impure

echo "Build done:"

RESULT="$(readlink -f ./result)"
echo "Applying now..."
"$Result/bin/switch-to-configuration" switch

echo "Airgap applied."