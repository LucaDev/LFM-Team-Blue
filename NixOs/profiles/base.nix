{ config, pkgs, lib, ... }:

{
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "de_DE.UTF-8";
  console.keyMap = "de";

  networking.hostName = "cold-Signer";

  #User mit Sudo
  users.users.user = {
    isNormalUser = true;
    description = "Admin";
    initialPassword = "changeme";
    extraGroups = [ "wheel" ];
  };

  security.sudo.wheelNeedsPassword = true;

  #hilfreiche Tools
  environment.systemPackages = with pkgs; [
    nano
    unzip
    #webcam zum QR-code scannen fuer sparrow
    v4l-utils
    gnupg
    coreutils
  ];

  environment.etc."scripts/psbt/psbt-approve.sh" = {
    source = ./files/wrappers/psbt-approve.sh;
    mode = "0755";
  };
  environment.etc."scripts/psbt/README.md" = {
    source = ./files/psbt/README.md;
    mode   = "0644";
  };


  environment.etc."scripts/setup/online.sh" = {
    source = ./files/wrappers/online.sh;
    mode   = "0755";
  };
  environment.etc."scripts/setup/setup.sh" = {
    source = ./files/wrappers/setup.sh;
    mode   = "0755";
  };
  environment.etc."scripts/setup/airgap.sh" = {
    source = ./files/wrappers/airgap.sh;
    mode   = "0755";
  };
  environment.etc."scripts/setup/mnt-USB.sh" = {
    source = ./files/wrappers/mnt-USB.sh;
    mode   = "0755";
  };
  environment.etc."scripts/setup/format-USB.sh" = {
    source = ./files/wrappers/format-USB.sh;
    mode   = "0755";
  };
  environment.etc."scripts/setup/README.md" = {
    source = ./files/setup/README.md;
    mode   = "0644";
  };


  environment.etc."scripts/auth/hash-keyGen.sh" = {
    source = ./files/wrappers/hash-keyGen.sh;
    mode   = "0755";
  };
  environment.etc."scripts/auth/hash-keyStore.sh" = {
    source = ./files/wrappers/hash-keyStore.sh;
    mode   = "0755";
  };
  environment.etc."scripts/auth/hash-verify.sh" = {
    source = ./files/wrappers/hash-verify.sh;
    mode   = "0755";
  };
  environment.etc."scripts/auth/README.md" = {
    source = ./files/auth/README.md;
    mode   = "0644";
  };


  #Legt Ordner beim Boot an (oder beim tmpfiles-setup)
  systemd.tmpfiles.rules = [
    "d /home/user/Desktop 0750 user users - -"
    "d /home/user/Desktop/psbt 0750 user users - -"
    "d /home/user/bin 0750 user users - -"
    "d /home/user/Desktop/scripts 0750 user users - -"
    "d /home/user/Desktop/scripts/auth 0750 user users - -"
    "d /home/user/Desktop/scripts/psbt 0750 user users - -"
    "d /home/user/Desktop/scripts/setup 0750 user users - -"
    "d /var/lib/psbt-guard 0700 root root - -"
    "d /var/lib/psbt-guard/gnupg 0700 root root - -"
    "d /var/lib/psbt-guard/identity 0700 root root - -"
    "d /mnt/usb 0755 root root - -"

    "L+ /home/user/Desktop/scripts/setup/online.sh - - - - /etc/scripts/setup/online.sh"
    "L+ /home/user/Desktop/scripts/setup/airgap.sh - - - - /etc/scripts/setup/airgap.sh"
    "L+ /home/user/Desktop/scripts/setup/setup.sh - - - - /etc/scripts/setup/setup.sh"
    "L+ /home/user/Desktop/scripts/setup/format-USB.sh - - - - /etc/scripts/setup/format-USB.sh"
    "L+ /home/user/Desktop/scripts/setup/mnt-USB.sh - - - - /etc/scripts/setup/mnt-USB.sh"
    "L+ /home/user/Desktop/scripts/setup/README.md - - - - /etc/scripts/setup/README.md"

    "L+ /home/user/Desktop/scripts/psbt/psbt-approve.sh - - - - /etc/scripts/psbt/psbt-approve.sh"
    "L+ /home/user/Desktop/scripts/psbt/README.md - - - - /etc/scripts/psbt/README.md"

    "L+ /home/user/Desktop/scripts/auth/hash-keyGen.sh - - - - /etc/scripts/auth/hash-keyGen.sh"
    "L+ /home/user/Desktop/scripts/auth/hash-keyStore.sh - - - - /etc/scripts/auth/hash-keyStore.sh"
    "L+ /home/user/Desktop/scripts/auth/hash-verify.sh - - - - /etc/scripts/auth/hash-verify.sh"
    "L+ /home/user/Desktop/scripts/auth/README.md - - - - /etc/scripts/auth/README.md"
  ];
      
  #Journald begrenzen (VM-Disk nicht zulaufen lassen)
  services.journald.extraConfig = ''
    SystemMaxUse=200M
    RuntimeMaxUse=150M
  '';

  
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