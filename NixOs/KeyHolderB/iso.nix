{ config, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")

    ./profiles/hardware-vm.nix
    ./profiles/base.nix
    ./profiles/gui.nix
    ./profiles/sparrow.nix
    ./profiles/network.nix
  ];

  isoImage.isoName = "nixos-cold-signer-sparrow.iso";

  users.users.admin.initialPassword = "admin";
}