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
    "d /home/user/psbt 0750 user users - -"
    "d /home/user/psbt/in 0750 user users - -"
    "d /home/user/psbt/out 0750 user users - -"
    "d /home/user/bin 0750 user users - -"
  ];

  #hilfreiche Tools
  environment.systemPackages = with pkgs; [
    nano
    unzip
    #webcam zum QR-code scannen fuer sparrow
    v4l-utils
  ];

  environment.etc."/scripts/psbt-inbox-status.sh" = {
    source = ./files/psbt-inbox-status.sh;
    mode = "0755";
  };

  environment.etc."/scripts/psbt-outbox-status.sh" = {
    source = ./files/psbt-outbox-status.sh;
    mode = "0755";
  };

  environment.etc."/scripts/psbt-hash.sh" = {
    source = ./files/psbt-hash.sh;
    mode = "0755";
  };

  environment.etc."/scripts/online.sh" = {
    source = ./files/online.sh;
    mode   = "0755";
  };

  environment.etc."/scripts/airgap.sh" = {
    source = ./files/airgap.sh;
    mode   = "0755";
  };

  environment.etc."/scripts/README.md" = {
    source = ./files/README.txt;
    mode   = "0644";
  };
  
  #Journald begrenzen (VM-Disk nicht zulaufen lassen)
  services.journald.extraConfig = ''
    SystemMaxUse=200M
    RuntimeMaxUse=150M
  '';

}