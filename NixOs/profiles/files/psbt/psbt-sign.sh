#!/usr/bin/env bash
set -euo pipefail

MNT="/mnt/usb"
GNUPGHOME="/var/lib/psbt-guard/gnupg"

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "[*] $*"; }
[[ $EUID -eq 0 ]] || die "Bitte als root ausführen."
mountpoint -q "$MNT" || die "Nicht gemountet: $MNT"

export GNUPGHOME
mkdir -p "$GNUPGHOME"
chmod 0700 "$GNUPGHOME" || true

# Release verify (Hot)
REL_JSON="$MNT/psbt/out/release.json"
REL_SIG="$MNT/psbt/out/release.json.sig"
if [[ -f "$REL_JSON" && -f "$REL_SIG" ]]; then
  info "Phase: RELEASE verify"
  gpg --verify "$REL_SIG" "$REL_JSON" >/dev/null 2>&1 || die "Release GPG verify fehlgeschlagen."

  FINAL_REL="$(grep -E '"final_psbt_path"' "$REL_JSON" | head -n1 | sed -E 's/.*"final_psbt_path"\s*:\s*"([^"]+)".*/\1/')"
  FINAL_HASH="$(grep -E '"final_psbt_sha256"' "$REL_JSON" | head -n1 | sed -E 's/.*"final_psbt_sha256"\s*:\s*"([^"]+)".*/\1/')"
  [[ -n "$FINAL_REL" && -n "$FINAL_HASH" ]] || die "release.json unlesbar."

  FINAL="$MNT/$FINAL_REL"
  [[ -f "$FINAL" ]] || die "Final PSBT fehlt: $FINAL_REL"

  CALC="$(sha256sum "$FINAL" | awk '{print $1}')"
  [[ "$CALC" == "$FINAL_HASH" ]] || die "Final Hash mismatch! expected=$FINAL_HASH got=$CALC"

  info "OK: RELEASE gültig. Broadcast ist freigegeben."
  exit 0
fi

# Approval verify (Key)
APP_JSON="$MNT/psbt/approval/approval.json"
APP_SIG="$MNT/psbt/approval/approval.json.sig"
if [[ -f "$APP_JSON" && -f "$APP_SIG" ]]; then
  info "Phase: APPROVAL verify"
  gpg --verify "$APP_SIG" "$APP_JSON" >/dev/null 2>&1 || die "Approval GPG verify fehlgeschlagen."

  PSBT_REL="$(grep -E '"for_signing_path"' "$APP_JSON" | head -n1 | sed -E 's/.*"for_signing_path"\s*:\s*"([^"]+)".*/\1/')"
  PSBT_HASH="$(grep -E '"for_signing_sha256"' "$APP_JSON" | head -n1 | sed -E 's/.*"for_signing_sha256"\s*:\s*"([^"]+)".*/\1/')"
  AID="$(grep -E '"approval_id"' "$APP_JSON" | head -n1 | sed -E 's/.*"approval_id"\s*:\s*"([^"]+)".*/\1/')"

  [[ -n "$PSBT_REL" && -n "$PSBT_HASH" && -n "$AID" ]] || die "approval.json unlesbar."
  PSBT="$MNT/$PSBT_REL"
  [[ -f "$PSBT" ]] || die "PSBT fehlt: $PSBT_REL"

  CALC="$(sha256sum "$PSBT" | awk '{print $1}')"
  [[ "$CALC" == "$PSBT_HASH" ]] || die "PSBT Hash mismatch! expected=$PSBT_HASH got=$CALC"

  info "OK: APPROVAL gültig. approval_id=$AID"
  info "Du darfst jetzt in Sparrow signieren: $PSBT_REL"
  exit 0
fi

die "Weder release.json(.sig) noch approval.json(.sig) gefunden."