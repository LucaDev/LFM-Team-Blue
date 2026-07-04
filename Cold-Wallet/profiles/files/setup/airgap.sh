#!/usr/bin/env bash
set -euo pipefail

SYS="/nix/var/nix/profiles/system"

[ "$(id -u)" -eq 0 ] || { echo "Bitte als root (pkexec) ausführen."; exit 1; }

echo "== AIRGAP aktivieren (Netz AUS) =="
"$SYS/bin/switch-to-configuration" switch

echo
echo "Status Interfaces (sollten DOWN sein):"
ip -brief link show | grep -vw lo || true
echo "Egress-Firewall:"
nft list table inet airgap-egress 2>/dev/null | grep -E 'hook output|policy' \
  || echo "  (Tabelle nicht gefunden)"
echo
echo "AIRGAP ist aktiv."