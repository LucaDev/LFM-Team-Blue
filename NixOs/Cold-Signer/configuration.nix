{ config, pkgs, ... }:

{
  imports = [   
    ./profiles/airgap-option.nix
    ./profiles/hardware-vm.nix 
    ./hardware-configuration.nix
    ./profiles/base.nix
    ./profiles/gui.nix
    ./profiles/sparrow.nix
    ./profiles/network.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  config.airgap = false; # Build-Mode
  
  airgap.enable = true;   # oder false

  system.stateVersion = "24.05";

}