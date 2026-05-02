#!/usr/bin/env bash
set -euo pipefail

CFG="/etc/nixos/configuration.nix"
FLAKE_DIR="/etc/nixos"
TARGET="cold"

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }
[ -f "$CFG" ] || { echo "ERROR: $CFG not found" >&2; exit 1; }

# 1) already false?
if grep -Eq '^\s*airgap\.enable\s*=\s*false\s*;' "$CFG"; then
  echo "airgap.enable is already false (in $CFG). Nothing to do."
  exit 0
fi

# 2) only replace if the setting exists (avoid appending in wrong scope)
if grep -Eq '^\s*airgap\.enable\s*=' "$CFG"; then
  sed -i -E 's/^\s*airgap\.enable\s*=\s*(true|false)\s*;/  airgap.enable = false;/' "$CFG"
  echo "Set airgap.enable=false"
else
  echo "ERROR: airgap.enable not found in $CFG. I won't append blindly (risk wrong scope)."
  echo "Add 'airgap.enable = true/false;' once in the correct module scope, then rerun."
  exit 1
fi

# 3) switch using flake (path: to avoid git+file behavior) + impure for dirty tree
echo "Switching (flake: path:${FLAKE_DIR}#${TARGET})..."
nixos-rebuild switch \
  --flake "path:${FLAKE_DIR}#${TARGET}" \
  --impure

echo "Online mode applied (airgap disabled)."
