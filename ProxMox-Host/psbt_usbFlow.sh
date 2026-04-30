#!/usr/bin/env bash
set -euo pipefail

# This represents the phyiscal inserting of the USH flashdrive simulated in proxmox.
# Afterwards it still needs to be manually mounted on the VM
# The commands are 
#   psbt_usbFlow hot
#   psbt_usbFlow signer
#   psbt_usbFlow keyb
#   psbt_usbFlow keyc
#   psbt_usbFlow <vmid>

# ==============================================================================
# CONFIG (anpassen)
# ==============================================================================
USB_IMG="/var/lib/vz/images/psbt-usb.qcow2"
SLOT="2"                       # scsi2
START_TIMEOUT=60               # Sekunden warten bis VM läuft
LOCK="/run/lock/psbt-usb.lock"

# VMIDs
HOT_VMID="101"
SIGNER_VMID="201"
KEYB_VMID="203"
KEYC_VMID="204"

# Names (nur UI)
HOT_NAME="hot"
SIGNER_NAME="signer"
KEYB_NAME="keyB"
KEYC_NAME="keyC"

# ==============================================================================
die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "[*] $*"; }
warn(){ echo "[!] $*" >&2; }

need_root(){ [[ $EUID -eq 0 ]] || die "Bitte als root ausführen."; }

lock(){
  mkdir -p "$(dirname "$LOCK")"
  exec 9>"$LOCK"
  flock -n 9 || die "Lock aktiv: ein anderer psbt-usb Prozess läuft gerade."
}

role_to_vmid(){
  case "${1:-}" in
    hot) echo "$HOT_VMID" ;;
    signer|coord|coordinator) echo "$SIGNER_VMID" ;;
    keyb) echo "$KEYB_VMID" ;;
    keyc) echo "$KEYC_VMID" ;;
    *) [[ "${1:-}" =~ ^[0-9]+$ ]] && echo "$1" || die "Unbekannte Rolle/VMID: $1" ;;
  esac
}

vmid_to_name(){
  local vmid="$1"
  case "$vmid" in
    "$HOT_VMID") echo "$HOT_NAME" ;;
    "$SIGNER_VMID") echo "$SIGNER_NAME" ;;
    "$KEYB_VMID") echo "$KEYB_NAME" ;;
    "$KEYC_VMID") echo "$KEYC_NAME" ;;
    *) echo "vm-$vmid" ;;
  esac
}

qm_running(){
  qm status "$1" 2>/dev/null | grep -q "status: running"
}

ensure_vm_running(){
  local vmid="$1"
  qm status "$vmid" &>/dev/null || die "VMID $vmid existiert nicht."

  if qm_running "$vmid"; then
    info "VMID $vmid ($(vmid_to_name "$vmid")) läuft bereits."
    return 0
  fi

  info "VMID $vmid ($(vmid_to_name "$vmid")) ist aus -> starte..."
  qm start "$vmid" >/dev/null

  local t=0
  while ! qm_running "$vmid"; do
    sleep 1
    t=$((t+1))
    if (( t >= START_TIMEOUT )); then
      die "VMID $vmid wurde nicht innerhalb von ${START_TIMEOUT}s running."
    fi
  done
  info "VMID $vmid läuft."
}

is_attached_to_vmid(){
  local vmid="$1"
  qm config "$vmid" | grep -E "^scsi${SLOT}:" | grep -Fq "$USB_IMG"
}

find_owner_vmid(){
  while read -r vmid _; do
    [[ "$vmid" =~ ^[0-9]+$ ]] || continue
    if is_attached_to_vmid "$vmid"; then
      echo "$vmid"; return 0
    fi
  done < <(qm list | awk 'NR>1 {print $1, $2}')
  return 1
}

attach_usb(){
  local vmid="$1"
  local owner
  if owner="$(find_owner_vmid 2>/dev/null)"; then
    [[ "$owner" == "$vmid" ]] || die "USB hängt bereits an VMID $owner. Erst dort detachen."
    info "USB hängt bereits an VMID $vmid."
    return 0
  fi

  local existing
  existing="$(qm config "$vmid" | grep -E "^scsi${SLOT}:" || true)"
  [[ -z "$existing" ]] || die "VMID $vmid hat scsi${SLOT} schon belegt: $existing"

  info "Attach: $USB_IMG -> VMID $vmid als scsi${SLOT}"
  qm set "$vmid" -scsi"${SLOT}" "$USB_IMG" >/dev/null
  info "Attached."
}

detach_usb(){
  local vmid="$1"
  local line
  line="$(qm config "$vmid" | grep -E "^scsi${SLOT}:" || true)"
  if [[ -z "$line" ]]; then
    info "Detach: scsi${SLOT} an VMID $vmid ist nicht belegt."
    return 0
  fi
  if ! echo "$line" | grep -Fq "$USB_IMG"; then
    die "scsi${SLOT} ist belegt, aber nicht durch $USB_IMG: $line"
  fi
  info "Detach: scsi${SLOT} von VMID $vmid"
  qm set "$vmid" -delete "scsi${SLOT}" >/dev/null
  info "Detached."
}

cmd_step(){
  local role="${1:-}"; shift || true
  [[ -n "$role" ]] || die "Usage: $0 <hot|signer|keyb|keyc|vmid> [message...]"
  local vmid; vmid="$(role_to_vmid "$role")"
  local name; name="$(vmid_to_name "$vmid")"

  ensure_vm_running "$vmid"
  attach_usb "$vmid"
  
  local DETACHED=0
  cleanup(){
    if [[ $DETACHED -eq 0 ]]; then
      warn "Cleanup: Detach (exit/abort) ..."
      detach_usb "$vmid" || true
    fi
  }
  trap cleanup EXIT INT TERM  

  echo "USB ist jetzt an VM '$name' (VMID $vmid) als scsi${SLOT} attached."
  echo
  echo "In der VM jetzt ausführen:"
  echo "  sudo mount /dev/disk/by-label/USB /mnt/usb"
  echo "  # Sparrow / Scripts ausführen"
  echo "  sync"
  echo "  sudo umount /mnt/usb"
  echo
  echo "================================================================================"
  read -r -p "ENTER zum Detach..." _

  detach_usb "$vmid"
  info "Fertig: USB detached von VM '$name' (VMID $vmid)."
 
  DETACHED=1
  trap - EXIT INT TERM
}


main(){
  need_root
  lock
  cmd_step "$@"
}

main "$@"
