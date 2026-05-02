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
  
  airgap.enable = false;   # Build-Mode
  system.stateVersion = "24.05";

  home-manager.users.user = { ... }: {
      programs.xfconf.enable = true;

      xfconf.settings = {
        thunar = {
          # Shell-Skripte per Doppelklick ausführen
          "misc-exec-shell-scripts-by-default" = true;
        };
      };
    };
}