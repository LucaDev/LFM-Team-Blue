#!/usr/bin/env bash
set -euo pipefail

MNT="/mnt/usb"
GNUPGHOME="/var/lib/psbt-guard/gnupg"

PSBT_DIR="$MNT/psbt"
AUTH_DIR="$PSBT_DIR/auth"
ARCH_DIR="$PSBT_DIR/archive"

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "[*] $*"; }

[[ $EUID -eq 0 ]] || die "Bitte als root ausführen."
mountpoint -q "$MNT" || die "Nicht gemountet: $MNT"

export GNUPGHOME
mkdir -p "$GNUPGHOME"
chmod 0700 "$GNUPGHOME" || true

# -------------------------------------------------------------------
# Input finden (Readme: /mnt/usb/psbt/unappr.<id>.psbt)
# -------------------------------------------------------------------
shopt -s nullglob
inputs=( "$PSBT_DIR"/unappr.*.psbt )
shopt -u nullglob

[[ ${#inputs[@]} -gt 0 ]] || die "Keine Input-PSBT gefunden: $PSBT_DIR/unappr.<id>.psbt"
[[ ${#inputs[@]} -eq 1 ]] || die "Mehrere unappr.*.psbt gefunden. Single-TX-Regel verletzt: ${inputs[*]}"

IN_UNSIGNED="${inputs[0]}"
BASENAME="$(basename "$IN_UNSIGNED")"         # unappr.<id>.psbt
ID="${BASENAME#unappr.}"
ID="${ID%.psbt}"

[[ -n "$ID" && "$ID" != "$BASENAME" ]] || die "Konnte <id> nicht aus Dateiname ableiten: $BASENAME"

OUT_APPR="$PSBT_DIR/appr.${ID}.psbt"

# Output/Dirs
mkdir -p "$AUTH_DIR" "$ARCH_DIR"

# -------------------------------------------------------------------
# Hashes berechnen
# -------------------------------------------------------------------
U_HASH="$(sha256sum "$IN_UNSIGNED" | awk '{print $1}')"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# -------------------------------------------------------------------
# Approved PSBT erzeugen (Readme: appr.<id>.psbt)
# -------------------------------------------------------------------
cp -f "$IN_UNSIGNED" "$OUT_APPR"
A_HASH="$(sha256sum "$OUT_APPR" | awk '{print $1}')"

# -------------------------------------------------------------------
# approval.json (+sig) erzeugen (Readme: psbt/auth/approval.json(.sig))
# Bindet die Approval-Entscheidung an appr.<id>.psbt via sha256
# -------------------------------------------------------------------
APP_JSON="$AUTH_DIR/approval.json"
APP_SIG="$AUTH_DIR/approval.json.sig"

cat > "$APP_JSON" <<EOF
{
  "type": "psbt-approval",
  "id": "${ID}",
  "created_utc": "${TS}",
  "unappr_path": "psbt/${BASENAME}",
  "unappr_sha256": "${U_HASH}",
  "appr_path": "psbt/$(basename "$OUT_APPR")",
  "appr_sha256": "${A_HASH}"
}
EOF

# GPG Secret Key muss vorhanden sein (Signer-Auth)
gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:' \
  || die "Kein GPG Secret Key in $GNUPGHOME (Signer Key fehlt)."

# Signiere approval.json (detached)
gpg --yes --detach-sign -o "$APP_SIG" "$APP_JSON"

# -------------------------------------------------------------------
# Archivieren: unappr.<id>.psbt nach psbt/archive/ verschieben (flach)
# -------------------------------------------------------------------
mv -f "$IN_UNSIGNED" "$ARCH_DIR/$BASENAME"

sync

info "APPROVAL erstellt (Signer-auth):"
info " - psbt/$(basename "$OUT_APPR")"
info " - psbt/auth/approval.json(.sig)"
info "Archiv: psbt/archive/$BASENAME"

umount "$MNT"

info "USB unmounted: $MNT"