#!/usr/bin/env bash
set -euo pipefail

MNT="/mnt/usb"
GNUPGHOME="/var/lib/psbt-guard/gnupg"

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "[*] $*"; }

[[ $EUID -eq 0 ]] || die "Bitte als root ausführen."
mountpoint -q "$MNT" || die "Nicht gemountet: $MNT"

VERIFIED=0

cleanup() {
  # NUR BEI NICHT-ERFOLG unmounten
  if [[ "$VERIFIED" -ne 1 ]]; then
    if mountpoint -q "$MNT"; then
      if umount "$MNT" >/dev/null 2>&1; then
        echo "[!] Not verified, unmounted." >&2
      else
        echo "[!] Cleanup: unmount failed for $MNT" >&2
      fi
    fi
  fi
}
trap cleanup EXIT

# Medium-Check (Hardening)
SRC_DEV="$(findmnt -n -o SOURCE --target "$MNT")"
[[ "$SRC_DEV" =~ ^/dev/ ]] || die "Mountpoint ist kein Blockdevice: $SRC_DEV"

LABEL="$(lsblk -no LABEL "$SRC_DEV" 2>/dev/null | head -n1 || true)"
[[ "$LABEL" == "USB" ]] || die "Falsches Medium (Label != USB)."

# GPG Home vorbereiten
export GNUPGHOME
mkdir -p "$GNUPGHOME"
chmod 0700 "$GNUPGHOME" || true

# ------------------------------------------------------------
# APPROVAL verify (KeyB/KeyC): psbt/auth/approval.json(.sig)
# ------------------------------------------------------------
APP_JSON="$MNT/psbt/auth/approval.json"
APP_SIG="$MNT/psbt/auth/approval.json.sig"

[[ -f "$APP_JSON" && -f "$APP_SIG" ]] || die "psbt/auth/approval.json(.sig) nicht gefunden."

info "Phase: APPROVAL verify (Signer -> Key)"
gpg --verify "$APP_SIG" "$APP_JSON" >/dev/null 2>&1 || die "Approval GPG verify fehlgeschlagen."

# Auslesen neuer Felder (Readme-konform)
PSBT_REL="$(grep -E '"appr_path"' "$APP_JSON" | head -n1 | sed -E 's/.*"appr_path"\s*:\s*"([^"]+)".*/\1/')"
PSBT_HASH="$(grep -E '"appr_sha256"' "$APP_JSON" | head -n1 | sed -E 's/.*"appr_sha256"\s*:\s*"([^"]+)".*/\1/')"
ID="$(grep -E '"id"' "$APP_JSON" | head -n1 | sed -E 's/.*"id"\s*:\s*"([^"]+)".*/\1/')"

[[ -n "$PSBT_REL" && -n "$PSBT_HASH" && -n "$ID" ]] || die "approval.json unlesbar (appr_path/appr_sha256/id fehlen)."

PSBT="$MNT/$PSBT_REL"
[[ -f "$PSBT" ]] || die "PSBT fehlt: $PSBT_REL"

CALC="$(sha256sum "$PSBT" | awk '{print $1}')"
[[ "$CALC" == "$PSBT_HASH" ]] || die "PSBT Hash mismatch! expected=$PSBT_HASH got=$CALC"

info "OK: APPROVAL gültig. id=$ID"
info "Du darfst jetzt in Sparrow signieren:"
info " - $PSBT_REL"
info "USB bleibt gemountet unter $MNT (für Sparrow)."

VERIFIED=1
exit 0