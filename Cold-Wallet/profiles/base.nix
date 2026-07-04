{ config, pkgs, lib, ... }:

{
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "de_DE.UTF-8";
  console.keyMap = "de";

  networking.hostName = "cold-Signer";

    users.users.user = {
      isNormalUser = true;
      description = "Admin";
      hashedPassword = "$6$MZj5odB7Ybpv3/rZ$eiX32rlH4uqjk9BsfSUeBhv7Pc4vMOCQrf73pP5b/EyLX9xIYTX0jqgQ/BjQ3sUeK/aePuwve3CYchIiYeDRh.";
      extraGroups = [ "wheel" ];
    };

  security.sudo.wheelNeedsPassword = true;

  #hilfreiche Tools
  environment.systemPackages = with pkgs; [
    nano
    unzip
    #webcam zum QR-code scannen fuer sparrow
    v4l-utils
    coreutils
  ];

  #============================================
  #Echte scripte (referenziert in warpper)
  #============================================
  environment.etc."scripts/setup/online.sh" = {
    source = ./files/setup/online.sh;
    mode   = "0755";
  };
  environment.etc."scripts/setup/setup.sh" = {
    source = ./files/setup/setup.sh;
    mode   = "0755";
  };
  environment.etc."scripts/setup/airgap.sh" = {
    source = ./files/setup/airgap.sh;
    mode   = "0755";
  };
  environment.etc."scripts/setup/mnt-USB.sh" = {
    source = ./files/setup/mnt-USB.sh;
    mode   = "0755";
  };
  environment.etc."scripts/setup/umnt-USB.sh" = {
    source = ./files/setup/umnt-USB.sh;
    mode   = "0755";
  };
  environment.etc."scripts/setup/format-USB.sh" = {
    source = ./files/setup/format-USB.sh;
    mode   = "0755";
  };

#===================================
#Wrappers
#===================================
  environment.etc."scripts/wrappers/online.sh" = {
    source = ./files/wrappers/online.sh;
    mode   = "0755";
  };
  environment.etc."scripts/wrappers/setup.sh" = {
    source = ./files/wrappers/setup.sh;
    mode   = "0755";
  };
  environment.etc."scripts/wrappers/airgap.sh" = {
    source = ./files/wrappers/airgap.sh;
    mode   = "0755";
  };
  environment.etc."scripts/wrappers/mnt-USB.sh" = {
    source = ./files/wrappers/mnt-USB.sh;
    mode   = "0755";
  };
  environment.etc."scripts/wrappers/umnt-USB.sh" = {
    source = ./files/wrappers/umnt-USB.sh;
    mode   = "0755";
  };
  environment.etc."scripts/wrappers/format-USB.sh" = {
    source = ./files/wrappers/format-USB.sh;
    mode   = "0755";
  };

#===========================
#Desktop page mit symlinks auf wrappers
#==============================

  #Legt Ordner beim Boot an (oder beim tmpfiles-setup)
  systemd.tmpfiles.rules = [
    "d /home/user/Desktop 0750 user users - -"
    "d /home/user/bin 0750 user users - -"
    "d /home/user/Desktop/scripts 0750 user users - -"
    "d /home/user/Desktop/scripts/setup 0750 user users - -"
    "d /mnt/usb 0755 root root - -"

    "L+ /home/user/Desktop/scripts/setup/online.sh - - - - /etc/scripts/wrappers/online.sh"
    "L+ /home/user/Desktop/scripts/setup/airgap.sh - - - - /etc/scripts/wrappers/airgap.sh"
    "L+ /home/user/Desktop/scripts/setup/setup.sh - - - - /etc/scripts/wrappers/setup.sh"
    "L+ /home/user/Desktop/scripts/setup/format-USB.sh - - - - /etc/scripts/wrappers/format-USB.sh"
    "L+ /home/user/Desktop/scripts/setup/mnt-USB.sh - - - - /etc/scripts/wrappers/mnt-USB.sh"
    "L+ /home/user/Desktop/scripts/setup/umnt-USB.sh - - - - /etc/scripts/wrappers/umnt-USB.sh"
  ];
  
 systemd.user.services.thunar-exec-shell-scripts = {
    description = "Thunar: execute shell scripts by default";
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.xfce.xfconf}/bin/xfconf-query \
          --channel thunar \
          --property /misc-exec-shell-scripts-by-default \
          --create --type bool --set true
      '';
    };
  };
  
}