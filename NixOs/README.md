
***

# Cold Wallet Infrastructure (NixOS + Sparrow Wallet)

## Overview

This project documents the setup of a **Bitcoin Cold‑Signer Infrastructure** based on **NixOS**, **Sparrow Wallet**, and **Proxmox VE**.  
The goal is a **reproducible, minimal, auditable and truly air‑gapped** cold‑wallet environment.

The setup is split into:

*   Bitcoin network / test infrastructure
*   NixOS ISO + system build
*   Proxmox VM definitions for cold keys and signer
*   Declarative OS + application configuration (NixOS)
*   Final air‑gapped hardening

***

## Bitcoin Network Preparation

Used for testing, development, and verification of PSBT flows.
Configured on the talos linux device where the hot wallet is also located

### Scripts

Additional scripts for the Bitcoin Network
Make scripts executable and run them in order:

```bash
chmod +x *.sh
./deploy.sh
./check.sh
./connect-nodes.sh
```

### Purpose

*   `deploy.sh` – deploys the Bitcoin nodes
*   `check.sh` – verifies node health
*   `connect-nodes.sh` – connects nodes within the Bitcoin network

***

## Proxmox VM Layout (Cold Wallets)

### General VM Rules

*   **No network device** for final cold systems
*   **UEFI only**
*   Minimal hardware footprint
*   Reproducible settings through declarative X.nix build

***

### Cold Key VMs (`cold-key-A`, `cold-key-B`)

| Setting         | Value                     |
| --------------- | ------------------------- |
| OS              | NixOS minimal (AMD/Intel) |
| HA              | Off                       |
| BIOS            | OVMF                      |
| Machine         | q35                       |
| Storage         | qcow2                     |
| Disk Size       | 10 GB                     |
| EFI Disk        | Enabled                   |
| Pre-Enroll Keys | Off                       |
| TPM             | Off                       |
| Network         | **None**                  |
| CPU Type        | Host                      |
| CPUs            | 1                         |
| Memory          | 1024 MB                   |
| NUMA            | Off                       |
| Ballooning      | Off                       |
| KSM             | Off                       |
| I/O Thread      | On                        |
| SSD Emulation   | On                        |
| Discard         | On                        |
| Backup          | Off                       |

***

### Cold Signer VM (`cold-signer`)

Same as cold-key VMs, except:

*   **Memory:** 2048 MB

***

## Direct Installation on NixOS (from ISO)

### Disk Setup (Example: `/dev/sda`)

```bash
sudo fdisk /dev/sda
```

Inside `fdisk`:

g
n
<Enter>
<Enter>
+1024M
t
1
n
<Enter>
<Enter>
w

***

### Filesystems and Labels

```bash
sudo mkfs.fat -F 32 -n NIXBOOT /dev/sda1
sudo mkfs.ext4 -L NIXROOT /dev/sda2
```

***

### Mount Target System

```bash
sudo mount /dev/disk/by-label/NIXROOT /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-label/NIXBOOT /mnt/boot
```

***

### Swapfile (2 GB)

```bash
sudo dd if=/dev/zero of=/mnt/.swapfile bs=1024 count=2097152
sudo chmod 600 /mnt/.swapfile
sudo mkswap /mnt/.swapfile
sudo swapon /mnt/.swapfile
```

***

## NixOS Configuration via GitHub

### Generate Initial Hardware Config

```bash
sudo nixos-generate-config --root /mnt
```

### Replace Default Config

```bash
sudo rm -rf /mnt/etc/nixos/*
```

### Clone Project Repo

```bash
git clone https://github.com/overflowdo/NixOsCold.git
```

### Copy Cold-Signer Configuration

```bash
sudo mv ~/NixOsCold/Cold-Signer/* /mnt/etc/nixos/
```

***

## Install NixOS to Disk

```bash
sudo nixos-install
```

Set passwords as prompted.
The corresponding username to that password will be root

Also user/user will be additionally available as credentials.

***

## Bootloader & Finalization

*   Ensure **EFI Disk is enabled in Proxmox**
*   **Remove ISO** after installation
*   Boot from disk (UEFI)

***

## Air‑Gap Mode (Final Security State)

> **Important:** Air‑Gap must only be enabled *after* the system is fully built.

In `/etc/nixos/configuration.nix`:

```nix
coldSigner.airgap.enable = true;
```

Apply safely:

```bash
sudo nixos-rebuild build
sudo ./result/bin/switch-to-configuration switch
```

***

### Air‑Gap Verification

This disables SSH, DHCP, NetworkManager and removes all active routes.

```bash
ip -br addr        # only lo
ip route           # no default route
ping 1.1.1.1       # must fail
systemctl status sshd # must be inactive
```

***

### Final Hard Air‑Gap (Exact Steps only applicable for Proxmox lab environment, reality will differ)

In **Proxmox**:

*   Remove Network Device completely  
    **or**
*   Attach VM to an isolated, non‑routed bridge

***

## Sparrow Wallet

*   Installed declaratively via `profiles/sparrow.nix`
*   Uses system package with correct executable resolution
*   Desktop entry created declaratively
*   Optional desktop shortcut symlink via `systemd.tmpfiles`

Start Sparrow:

```bash
sparrow-desktop
```

***

## Design Principles

*   Declarative, reproducible system state
*   Minimal attack surface
*   Explicit build → switch separation
*   OS‑level + hypervisor‑level air‑gap
*   No implicit defaults or hidden state

***

## Status

✅ ISO build reproducible  
✅ NixOS installation automated  
✅ Sparrow Wallet functional  
✅ Desktop integration done  
✅ Air‑Gap validated

***