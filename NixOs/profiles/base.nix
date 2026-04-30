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

  environment.etc."scripts/psbt-inbox-status.sh" = {
    source = ./files/psbt-inbox-status.sh;
    mode = "0755";
  };

  environment.etc."scripts/psbt-outbox-status.sh" = {
    source = ./files/psbt-outbox-status.sh;
    mode = "0755";
  };

  environment.etc."scripts/psbt-guard.sh" = {
    source = ./files/psbt-guard.sh;
    mode = "0755";
  };

  environment.etc."scripts/online.sh" = {
    source = ./files/online.sh;
    mode   = "0755";
  };

  environment.etc."scripts/airgap.sh" = {
    source = ./files/airgap.sh;
    mode   = "0755";
  };

  environment.etc."scripts/hash-keyGen.sh" = {
    source = ./files/hash-keyGen.sh;
    mode   = "0755";
  };

  environment.etc."scripts/hash-keyStore.sh" = {
    source = ./files/hash-keyStore.sh;
    mode   = "0755";
  };
  
  environment.etc."scripts/README.md" = {
    source = ./files/README.md;
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

    "L+ /home/user/Desktop/scripts/setup/online.sh - - - - /etc/scripts/online.sh"
    "L+ /home/user/Desktop/scripts/setup/airgap.sh - - - - /etc/scripts/airgap.sh"
    "L+ /home/user/Desktop/scripts/setup/README.md - - - - /etc/scripts/README.md"

    "L+ /home/user/Desktop/scripts/psbt/psbt-approve.sh - - - - /etc/scripts/psbt-approve.sh"
    "L+ /home/user/Desktop/scripts/psbt/README.md - - - - /etc/scripts/psbt/README.md"

    "L+ /home/user/Desktop/scripts/auth/hash-keyGen.sh - - - - /etc/scripts/hash-keyGen.sh"
    "L+ /home/user/Desktop/scripts/auth/hash-keyStore.sh - - - - /etc/scripts/hash-keyStore.sh"
    "L+ /home/user/Desktop/scripts/auth/hash-verify.sh - - - - /etc/scripts/hash-verify.sh"
    "L+ /home/user/Desktop/scripts/auth/README.md - - - - /etc/scripts/README.md"
  ];
      
  #Journald begrenzen (VM-Disk nicht zulaufen lassen)
  services.journald.extraConfig = ''
    SystemMaxUse=200M
    RuntimeMaxUse=150M
  '';

}