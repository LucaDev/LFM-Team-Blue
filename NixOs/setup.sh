#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/sda"
EFI_SIZE="1024M"

HOSTNAME="cold-signer"
TARGET_USER="user"

REPO_URL="https://github.com/overflowdo/NixOsCold.git"
REPO_SUBDIR="Cold-Signer"   # Ordner innerhalb des Repos, der configuration.nix + profiles enthält

SWAP_SIZE_GB="2"

echo "[1/9] Check disk exists: $DISK"
lsblk "$DISK" >/dev/null

echo "[2/9] Partitioning $DISK (GPT + EFI + ROOT)"
sgdisk --zap-all "$DISK"
sgdisk -og "$DISK"
sgdisk -n 1:0:+"$EFI_SIZE" -t 1:ef00 -c 1:"NIXBOOT" "$DISK"
sgdisk -n 2:0:0           -t 2:8300 -c 2:"NIXROOT" "$DISK"
partprobe "$DISK"
sleep 2

echo "[3/9] Formatting partitions (FAT32 EFI + EXT4 root)"
mkfs.fat -F 32 "${DISK}1"
fatlabel "${DISK}1" NIXBOOT

mkfs.ext4 -F -L NIXROOT "${DISK}2"

echo "[4/9] Mounting"
mount /dev/disk/by-label/NIXROOT /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/NIXBOOT /mnt/boot

echo "[5/9] Creating swapfile (${SWAP_SIZE_GB}G)"
fallocate -l "${SWAP_SIZE_GB}G" /mnt/.swapfile
chmod 600 /mnt/.swapfile
mkswap /mnt/.swapfile
swapon /mnt/.swapfile

echo "[6/9] Generate hardware config"
nixos-generate-config --root /mnt

echo "[7/9] Replace /mnt/etc/nixos with repo content"
rm -rf /mnt/etc/nixos/*
mkdir -p /mnt/etc/nixos

git clone --depth 1 "$REPO_URL" /mnt/etc/nixos/.repo

if [[ -n "$REPO_SUBDIR" ]]; then
  if [[ ! -d "/mnt/etc/nixos/.repo/$REPO_SUBDIR" ]]; then
    echo "ERROR: Repo subdir not found: $REPO_SUBDIR"
    echo "Repo content:"
    ls -la /mnt/etc/nixos/.repo
    exit 1
  fi
  cp -a "/mnt/etc/nixos/.repo/$REPO_SUBDIR/." /mnt/etc/nixos/
else
  cp -a /mnt/etc/nixos/.repo/. /mnt/etc/nixos/
fi

rm -rf /mnt/etc/nixos/.repo

echo "[8/9] Ensure bootloader + swap is configured (patch if missing)"
# Ensure swap is persistent across boots by adding swapDevices if not already present
if ! grep -q "swapDevices" /mnt/etc/nixos/hardware-configuration.nix; then
  cat >> /mnt/etc/nixos/hardware-configuration.nix <<'EOF'

swapDevices = [
  { device = "/.swapfile"; }
];
EOF
fi

# Make sure configuration imports hardware-configuration.nix
if ! grep -q "hardware-configuration.nix" /mnt/etc/nixos/configuration.nix; then
  echo "WARNING: configuration.nix does not import hardware-configuration.nix. Please fix in repo."
fi

# Ensure system is bootable (UEFI/systemd-boot)
if ! grep -q "boot.loader.systemd-boot.enable" /mnt/etc/nixos/configuration.nix; then
  cat >> /mnt/etc/nixos/configuration.nix <<'EOF'

boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;
EOF
fi

echo "[9/9] Install NixOS"
nixos-install --no-root-passwd

echo "DONE. Remove ISO in Proxmox and reboot."