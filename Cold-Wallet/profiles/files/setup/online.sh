#!/usr/bin/env bash
set -euo pipefail

SYS="/nix/var/nix/profiles/system"
SPEC="$SYS/specialisation/online"

[ "$(id -u)" -eq 0 ] || { echo "Bitte als root (pkexec) ausführen."; exit 1; }

[ -x "$SPEC/bin/switch-to-configuration" ] || {
  echo "FEHLER: online-specialisation nicht gefunden ($SPEC)."
  echo "Wurde das System mit 'specialisation.online' gebaut?"
  exit 1
}

echo "== ONLINE aktivieren (Netz AN, nur zum Registrieren) =="
"$SPEC/bin/switch-to-configuration" switch

# Interfaces, die der Airgap heruntergefahren hat, wieder hochbringen
for i in $(ls /sys/class/net); do
  [ "$i" = "lo" ] && continue
  ip link set "$i" up || true
done

# DHCP anstoßen und kurz warten
systemctl restart dhcpcd 2>/dev/null || true
sleep 2

echo
echo "Status (sollte eine IP zeigen):"
ip -brief addr show | grep -vw lo || true
echo
echo "ONLINE aktiv. Zum Zurückschalten: airgap.sh doppelklicken"
echo "(oder einfach rebooten — der Standard ist airgapped)."