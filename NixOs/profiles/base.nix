{ config, pkgs, ... }:

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

  #Legt Ordner beim Boot an (oder beim tmpfiles-setup)
  systemd.tmpfiles.rules = [
    "d /home/user/Desktop 0750 user users - -"
    "d /home/user/Desktop/psbt 0750 user users - -"
    "d /home/user/Desktop/psbt/in 0750 user users - -"
    "d /home/user/Desktop/psbt/out 0750 user users - -"
    "d /home/user/bin 0750 user users - -"
    "d /home/user/Desktop/scripts 0750 user users - -"
  ];

  #hilfreiche Tools
  environment.systemPackages = with pkgs; [
    nano
    unzip
    #webcam zum QR-code scannen fuer sparrow
    v4l-utils
  ];

  environment.etc."/home/user/Desktop/scripts/psbt-inbox-status.sh" = {
    source = ./files/psbt-inbox-status.sh;
    mode = "0755";
  };

  environment.etc."/home/user/Desktop/scripts/psbt-outbox-status.sh" = {
    source = ./files/psbt-outbox-status.sh;
    mode = "0755";
  };

  environment.etc."/home/user/Desktop/scripts/psbt-hash.sh" = {
    source = ./files/psbt-hash.sh;
    mode = "0755";
  };

  environment.etc."/home/user/Desktop/scripts/online.sh" = {
    source = ./files/online.sh;
    mode   = "0755";
  };

  environment.etc."/home/user/Desktop/scripts/airgap.sh" = {
    source = ./files/airgap.sh;
    mode   = "0755";
  };

  environment.etc."/home/user/Desktop/scripts/README.md" = {
    source = ../files/README.md;
    mode   = "0644";
  };
  
  #Journald begrenzen (VM-Disk nicht zulaufen lassen)
  services.journald.extraConfig = ''
    SystemMaxUse=200M
    RuntimeMaxUse=150M
  '';

}