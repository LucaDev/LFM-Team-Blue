{ config, pkgs, modulesPath, lib, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_scsi"
  ];

  # USB bewusst steuern
  services.udisks2.enable = lib.mkForce false;
}