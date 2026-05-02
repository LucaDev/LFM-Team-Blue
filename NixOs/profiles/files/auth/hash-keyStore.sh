#!/usr/bin/env bash
set -euo pipefail

# =========================
# Konfiguration
# =========================
MNT="/mnt/usb"

STATE_DIR="/var/lib/psbt-guard"
GNUPGHOME="$STATE_DIR/gnupg"

PUB_USB="$MNT/psbt/identity/signer-pubkey.asc"
META_USB="$MNT/psbt/identity/signer-identity.txt"

CFG="/etc/nixos/configuration.nix"

# 1 = nur lo darf UP sein (KeyB/KeyC)
# 0 = Airgap-Check aus (Hot)
REQUIRE_AIRGAP="${REQUIRE_AIRGAP:-1}"

# =========================
# Helper
# =========================
die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "[*] $*"; }

[[ $EUID -eq 0 ]] || die "Bitte als root ausführen."

IMPORTED=0
# =========================
# 0. Airgap sanity check (ignoriert lo)
# =========================
if [[ "$REQUIRE_AIRGAP" == "1" ]]; then
  if grep -Eq '^\s*airgap\.enable\s*=\s*false\s*;' "$CFG"; then
    echo "airgap enabled"
  else
    exit 0
  fi
fi

# =========================
# 1. Wechselmedium prüfen
# =========================
mountpoint -q "$MNT" || die "Nicht gemountet: $MNT"
[[ -f "$PUB_USB"  ]] || die "Fehlt: $PUB_USB"
[[ -f "$META_USB" ]] || die "Fehlt: $META_USB"

cleanup() {
  # Nur wenn gemountet, versuchen zu unmounten
  if mountpoint -q "$MNT"; then
    if umount "$MNT" >/dev/null 2>&1; then
      if [[ "$IMPORTED" -ne 1 ]]; then
        echo "[!] Not Imported, unmounted." >&2
      else
        echo "[*] Imported, unmounted."
      fi
    else
      echo "[!] Cleanup: unmount failed for $MNT" >&2
    fi
  fi
}
trap cleanup EXIT

SRC_DEV="$(findmnt -n -o SOURCE --target "$MNT")"
[[ "$SRC_DEV" =~ ^/dev/ ]] || die "Mountpoint ist kein Blockdevice: $SRC_DEV"
info "Wechselmedium erkannt: $SRC_DEV"

#Label-check gegen Verwechslung
LABEL="$(lsblk -no LABEL "$SRC_DEV" 2>/dev/null | head -n1 || true)"
[[ "$LABEL" == "USB" ]] || die "Falsches Medium (Label != USB)."

# =========================
# 2. GNUPG State vorbereiten
# =========================
mkdir -p "$GNUPGHOME"
chmod 0700 "$GNUPGHOME" || true
export GNUPGHOME

# =========================
# 3.1 Identity prüfen (SHA256)
# =========================
echo ""
echo "==========================="
EXPECTED_SHA="$(awk -F': ' '/^pubkey_sha256:/ {print $2}' "$META_USB" | tr -d '\r')"
[[ -n "$EXPECTED_SHA" ]] || die "Konnte pubkey_sha256 nicht aus $META_USB lesen"

ACTUAL_SHA="$(sha256sum "$PUB_USB" | awk '{print $1}')"
[[ "$EXPECTED_SHA" == "$ACTUAL_SHA" ]] || die "PubKey SHA mismatch! expected=$EXPECTED_SHA actual=$ACTUAL_SHA"

info "Identity OK (PubKey SHA256 passt)."

echo "============================"
echo ""

# =========================
# 3.2 Fingerprint kontrollieren
# =========================
#Fingerprint aus META lesen (erwartet)
echo "============================"
EXPECTED_FPR="$(awk -F': *' '/^fingerprint:/ {print $2}' "$META_USB" | tr -d '\r' | tr -d ' ')"
[[ -n "$EXPECTED_FPR" ]] || die "Konnte fingerprint nicht aus $META_USB lesen"
info "Erwarteter Fingerprint (META): $EXPECTED_FPR"

# Fingerprint aus PUB-Datei bestimmen
PUB_FPR="$(
  gpg --batch --quiet --with-colons --import-options show-only --import "$PUB_USB" 2>/dev/null \
    | awk -F: '/^fpr:/ {print $10; exit}'
)"
[[ -n "$PUB_FPR" ]] || die "Konnte Fingerprint nicht aus $PUB_USB bestimmen"
info "Fingerprint (aus USB): $PUB_FPR"

# Fingerprints vergleichen, sodass public Key nicht ausgetauscht wurde (allgemeinee Manipulationsschutz)
[[ "$EXPECTED_FPR" == "$PUB_FPR" ]] || die "Fingerprint mismatch! expected=$EXPECTED_FPR pub=$PUB_FPR"
info "Identity OK (Fingerprint passt)."

echo "============================"
echo ""

# Chain of trust für das initiale aufsetzen
info ""
info "OUT-OF-BAND CHECK:"
info "Vergleiche das mit dem Fingerprint, den du auf dem Signer offline notiert hast."
read -r -p "Stimmt der Fingerprint überein? [Y/N] " ans
case "${ans,,}" in
  y|yes) info "OK, Fingerprint bestätigt." ;;
  *) die "Abbruch durch Benutzer: Fingerprint nicht bestätigt." ;;
esac

# =========================
# 4. Public Key importieren
# =========================
info "Importiere Signer Public Key…"
gpg --import "$PUB_USB" >/dev/null

info "OK. Vorhandene Keys:"
gpg --list-keys

# =========================
# 5. Sync & Unmount
# =========================
IMPORTED=1

sync