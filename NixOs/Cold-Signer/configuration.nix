{ config, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

config.airgap = false; # Build-Mode
  
  services.resolved.enable = true;

  networking.nameservers = [
    "1.1.1.1"
    "8.8.8.8"
  ];


  imports = [   
    ./profiles/hardware-vm.nix 
    ./hardware-configuration.nix
    ./profiles/base.nix
    ./profiles/gui.nix
    ./profiles/sparrow.nix
    ./profiles/network.nix
  ];

}