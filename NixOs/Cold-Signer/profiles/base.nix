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

  environment.etc."cold/scripts/psbt-inbox-status.sh" = {
    source = ./files/psbt-inbox-status.sh;
    mode = "0755";
  };

  environment.etc."cold/scripts/psbt-outbox-status.sh" = {
    source = ./files/psbt-outbox-status.sh;
    mode = "0755";
  };

  environment.etc."cold/scripts/psbt-hash.sh" = {
    source = ./files/psbt-hash.sh;
    mode = "0755";
  };

  environment.etc."cold/scripts/README.txt" = {
    source = ./files/README.txt;
    mode   = "0644";
  };
  
  #Journald begrenzen (VM-Disk nicht zulaufen lassen)
  services.journald.extraConfig = ''
    SystemMaxUse=200M
    RuntimeMaxUse=150M
  '';

}