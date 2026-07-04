{ config, pkgs, lib, ... }:

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

  nix.settings.download-buffer-size = 268435456; # 256MB
  
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
  };
  
  airgap.enable = true;

  specialisation.online.configuration = {
    airgap.enable = lib.mkForce false;
  };

  cold.sparrowNetwork = "regtest";

  boot.loader.systemd-boot.editor = false;

  editor = false

  system.stateVersion = "24.05";
}