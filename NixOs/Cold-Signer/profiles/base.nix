{ config, pkgs, ... }:

{
  system.stateVersion = "24.11";

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "de_DE.UTF-8";
  console.keyMap = "de";

  networking.hostName = "cold-Signer";

  #User mit Sudo
  users.users.admin = {
    isNormalUser = true;
    description = "Admin";
    extraGroups = [ "wheel" ];
  };

  security.sudo.wheelNeedsPassword = true;

  #Legt Ordner beim Boot an (oder beim tmpfiles-setup)
  systemd.tmpfiles.rules = [
    "d /home/admin/psbt 0750 admin users - -"
    "d /home/admin/psbt/in 0750 admin users - -"
    "d /home/admin/psbt/out 0750 admin users - -"
    "d /home/admin/bin 0750 admin users - -"
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