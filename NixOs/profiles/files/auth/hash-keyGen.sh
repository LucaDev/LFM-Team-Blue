#!/usr/bin/env bash
set -euo pipefail

# =========================
# Konfiguration
# =========================
MNT="/mnt/usb"

STATE_DIR="/var/lib/psbt-guard"
GNUPGHOME="$STATE_DIR/gnupg"
LOCAL_ID="$STATE_DIR/identity"

USB_ID_DIR="$MNT/psbt/identity"

KEY_NAME_REAL="PSBT Signer Approval"
KEY_NAME_EMAIL="signer@airgap"
KEY_BITS="4096"

# =========================
# Helper
# =========================
die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "[*] $*"; }

# root erzwingen (weil /var/lib/..)
[[ $EUID -eq 0 ]] || die "Bitte als root ausführen."

# Alle files mit restriktiven Rechten erstellen
umask 077

# =========================
# 0. Airgap sanity check (ignoriert lo)
# =========================
# robust: erlaubt nur "lo" als UP
if ip -o link show up | awk -F': ' '{print $2}' | grep -qvx "lo"; then
  die "Netzwerk-Interface ist UP (außer lo). Bitte erst airgap aktivieren."
fi

# =========================
# 1. Wechselmedium prüfen (bewusster mount)
# =========================
if ! mountpoint -q "$MNT"; then
  die "Kein Wechselmedium gemountet unter $MNT"
fi

SRC_DEV="$(findmnt -n -o SOURCE --target "$MNT")"
[[ "$SRC_DEV" =~ ^/dev/ ]] || die "Mountpoint ist kein Blockdevice: $SRC_DEV"
info "Wechselmedium erkannt: $SRC_DEV"

LABEL="$(lsblk -no LABEL "$SRC_DEV" 2>/dev/null | head -n1 || true)"
[[ "$LABEL" == "USB" ]] || die "Falsches Medium (Label != USB)."

# =========================
# 2. Zielverzeichnisse vorbereiten
# =========================
mkdir -p "$STATE_DIR" "$GNUPGHOME" "$LOCAL_ID" "$USB_ID_DIR"
chmod 0700 "$STATE_DIR" "$GNUPGHOME" "$LOCAL_ID" "$USB_ID_DIR" || true
export GNUPGHOME

# =========================
# 3. GPG Key erzeugen (nur wenn noch keiner existiert)
# =========================
if gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:'; then
  die "Es existiert bereits ein GPG Private Key in $GNUPGHOME. Abbruch."
fi

info "Erzeuge neuen GPG Key (offline)…"

cat > "$STATE_DIR/keyparams" <<EOF
%no-protection
Key-Type: RSA
Key-Length: $KEY_BITS
Name-Real: $KEY_NAME_REAL
Name-Email: $KEY_NAME_EMAIL
Expire-Date: 0
%commit
EOF

gpg --batch --gen-key "$STATE_DIR/keyparams"

# =========================
# 4. Public Key + Fingerprint exportieren
# =========================
FP="$(gpg --list-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')"
[[ -n "$FP" ]] || die "Kein Fingerprint gefunden"

PUB_LOCAL="$LOCAL_ID/signer-pubkey.asc"
META_LOCAL="$LOCAL_ID/signer-identity.txt"

gpg --export --armor "$FP" > "$PUB_LOCAL"
chmod 0444 "$PUB_LOCAL"

PUB_SHA="$(sha256sum "$PUB_LOCAL" | awk '{print $1}')"

cat > "$META_LOCAL" <<EOF
fingerprint:   $FP
pubkey_sha256: $PUB_SHA
created_utc:   $(date -u +"%Y-%m-%dT%H:%M:%SZ")
source_dev:    $SRC_DEV
EOF
chmod 0444 "$META_LOCAL"

# USB (ohne signer/ Unterordner)
cp -f "$PUB_LOCAL"  "$USB_ID_DIR/signer-pubkey.asc"
cp -f "$META_LOCAL" "$USB_ID_DIR/signer-identity.txt"
chmod 0444 "$USB_ID_DIR/signer-pubkey.asc" "$USB_ID_DIR/signer-identity.txt" || true

info "Public Key exportiert nach USB:"
info " - $USB_ID_DIR/signer-pubkey.asc"
info " - $USB_ID_DIR/signer-identity.txt"

# =========================
# 5. Sync & Eject
# =========================
rm -f "$STATE_DIR/keyparams"

info "Bitte notiere den fingerprint $FP offline und halte ihn bereit für den Import auf den Key-Holdern. Dieser wird benötigt zur Verifikation, dass der Public Key nicht ausgetauscht wurde."
gpg --fingerprint "$FP"


sync
info "Daten geschrieben. Hänge Wechselmedium aus…"
umount "$MNT" || die "Konnte $MNT nicht aushängen"

info "FERTIG."
info "Wechselmedium kann jetzt physisch entfernt werden."