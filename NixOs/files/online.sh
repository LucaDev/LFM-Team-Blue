
#!/usr/bin/env bash
set -euo pipefail

CFG="/etc/nixos/configuration.nix"

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }
[ -f "$CFG" ] || { echo "ERROR: $CFG not found" >&2; exit 1; }

# 1) already false?

if grep -Eq '^\s*airgap\.enable\s*=\s*false\s*;' "$CFG"; then
  echo "airgap.enable is already false (in $CFG). Nothing to do."
  exit 0
fi

sed -i -E 's/^\s*airgap\.enable\s*=\s*(true|false)\s*;/  airgap.enable = false;/' "$CFG"
echo "Set airgap.enable=false"

# switch
nixos-rebuild switch
