{ config, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" ];
    boot.kernelModules = [ "usb_storage" "uas" "uvcvideo" ];
  boot.extraModulePackages = [ ];

  boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-label/NIXCRYPT";

  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXBOOT";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  swapDevices = [ ];
  boot.kernel.sysctl."vm.swappiness" = 0;
  zramSwap.enable = false;

  #USB nur bewusst mounten
  services.udisks2.enable = false;
}