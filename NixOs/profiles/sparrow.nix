{ config, pkgs, lib, ... }:

let
  sparrowPkg =
    if pkgs ? sparrow-wallet then pkgs.sparrow-wallet
    else if pkgs ? sparrow then pkgs.sparrow
    else throw "No sparrow package found in this nixpkgs";

    sparrowExec = lib.getExe sparrowPkg;
in
{
  environment.systemPackages = [
    sparrowPkg
    pkgs.xterm
  ];

  environment.etc."xdg/applications/sparrow.desktop" = {
    mode = "0644";
    text = ''
      [Desktop Entry]
      Name=Sparrow Wallet
      Exec=${sparrowExec}
      Type=Application
      Categories=Finance;
      Terminal=false
    '';
  };

  # Desktop-Shortcut anlegen (mit Desktop anlegen)
  # L+ = Symlink fuer Aenderungen
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /home/user/Desktop 0755 user users - -"
    "L+ /home/user/Desktop/sparrow.desktop - - - - /etc/xdg/applications/sparrow.desktop"
  ];
}