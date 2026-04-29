#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Konfiguration (optional anpassen)
# ==============================================================================

DEFAULT_MNT="/mnt/psbtusb"
APPROVAL_JSON_REL="psbt/approval.json"
APPROVAL_SIG_REL="psbt/approval.json.sig"

# Wie erkennen wir Rollen?
# - signer: hostname exakt "signer" oder beginnt mit "signer"
# - key:    hostname beginnt mit "key" (keyb, keyc, keyA, keyB, keyC etc.)
#
# Passe die Regex bei Bedarf an.
SIGNER_RE='^signer($|[-].*)'
KEY_RE='^key($|[a-zA-Z0-9_-].*)'

# ==============================================================================
die() { echo "ERROR: $*" >&2; exit 1; }

host_short() {
  # robust: erst hostnamectl, dann hostname
  local h=""
  h="$(hostnamectl --static 2>/dev/null || true)"
  if [[ -z "$h" ]]; then
    h="$(hostname -s 2>/dev/null || true)"
  fi
  [[ -n "$h" ]] || die "Konnte Hostname nicht ermitteln."
  echo "$h"
}

require_signer() {
  local h; h="$(host_short)"
  if ! [[ "$h" =~ $SIGNER_RE ]]; then
    echo "ABORT: Dieses Kommando darf NUR auf dem SIGNER laufen. (hostname='$h')" >&2
    exit 1
  fi
}

require_key() {
  local h; h="$(host_short)"
  if ! [[ "$h" =~ $KEY_RE ]]; then
    echo "ABORT: Dieses Kommando darf NUR auf einer KEY-VM laufen. (hostname='$h')" >&2
    exit 1
  fi
}

require_mounted() {
  local mnt="$1"
  if ! mountpoint -q "$mnt"; then
    echo "ABORT: Mountpoint ist nicht gemountet: $mnt" >&2
    exit 1
  fi
}

sha256_of_file() {
  sha256sum "$1" | awk '{print $1}'
}

json_get() {
  # minimaler JSON-Extractor für genau dieses flache Format: "key": "value"
  # Usage: json_get <file> <key>
  local file="$1"
  local key="$2"
  grep -E "\"$key\"[[:space:]]*:" "$file" | head -n1 | sed -E "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/"
}

cmd_approve() {
  require_signer
  local mnt="${1:-$DEFAULT_MNT}"
  local psbt_rel="${2:-}"

  [[ -n "$psbt_rel" ]] || die "Usage: psbt-guard approve [mount] <psbt-relative-path>"
  require_mounted "$mnt"

  local psbt_path="$mnt/$psbt_rel"
  [[ -f "$psbt_path" ]] || die "PSBT file not found: $psbt_path"

  local app_json="$mnt/$APPROVAL_JSON_REL"
  local app_sig="$mnt/$APPROVAL_SIG_REL"
  mkdir -p "$(dirname "$app_json")"

  local hash ts hn
  hash="$(sha256_of_file "$psbt_path")"
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  hn="$(host_short)"

  cat > "$app_json" <<EOF
{
  "type": "psbt-approval",
  "created_utc": "$ts",
  "approved_by": "$hn",
  "psbt_path": "$psbt_rel",
  "psbt_sha256": "$hash"
}
EOF

  # Signatur: Private GPG key bleibt auf signer-VM
  gpg --yes --armor --detach-sign -o "$app_sig" "$app_json"
  sync

  echo "OK: Approval erstellt:"
  echo " - $APPROVAL_JSON_REL"
  echo " - $APPROVAL_SIG_REL"
  echo " - psbt: $psbt_rel"
  echo " - sha256: $hash"
}

cmd_verify() {
  require_key
  local mnt="${1:-$DEFAULT_MNT}"
  require_mounted "$mnt"

  local app_json="$mnt/$APPROVAL_JSON_REL"
  local app_sig="$mnt/$APPROVAL_SIG_REL"

  [[ -f "$app_json" ]] || { echo "ABORT: approval.json fehlt: $APPROVAL_JSON_REL" >&2; exit 1; }
  [[ -f "$app_sig"  ]] || { echo "ABORT: approval.json.sig fehlt: $APPROVAL_SIG_REL" >&2; exit 1; }

  # 1) Signatur prüfen (Public Key vom signer muss importiert sein!)
  if ! gpg --verify "$app_sig" "$app_json" >/dev/null 2>&1; then
    echo "ABORT: GPG verify failed (Signer-Public-Key importiert? Datei manipuliert?)." >&2
    exit 1
  fi

  # 2) Pfad + Hash lesen
  local psbt_rel expected_hash
  psbt_rel="$(json_get "$app_json" "psbt_path")"
  expected_hash="$(json_get "$app_json" "psbt_sha256")"
  [[ -n "$psbt_rel" && -n "$expected_hash" ]] || { echo "ABORT: approval.json unlesbar." >&2; exit 1; }

  local psbt_path="$mnt/$psbt_rel"
  [[ -f "$psbt_path" ]] || { echo "ABORT: PSBT fehlt: $psbt_rel" >&2; exit 1; }

  # 3) Hash der PSBT prüfen
  local calc
  calc="$(sha256_of_file "$psbt_path")"
  if [[ "$calc" != "$expected_hash" ]]; then
    echo "ABORT: PSBT hash mismatch!" >&2
    echo " expected: $expected_hash" >&2
    echo " got:      $calc" >&2
    exit 1
  fi

  echo "OK: Approval gültig. Diese PSBT ist vom SIGNER freigegeben:"
  echo " - psbt:   $psbt_rel"
  echo " - sha256: $expected_hash"
}

usage() {
  cat <<EOF
psbt-guard (single file für signer + key VMs)

Usage:
  psbt-guard approve [mount] <psbt-relative-path>   # nur auf signer
  psbt-guard verify  [mount]                        # nur auf key*

Defaults:
  mount = $DEFAULT_MNT
  approval json = $APPROVAL_JSON_REL
  approval sig  = $APPROVAL_SIG_REL

Role detection:
  signer hostname regex: $SIGNER_RE
  key    hostname regex: $KEY_RE
EOF
}

case "${1:-}" in
  approve) shift; cmd_approve "$@" ;;
  verify)  shift; cmd_verify  "$@" ;;
  *) usage; exit 1 ;;
esac
