{ pkgs, lib, pkgsUnstable, ... }:

let
  sparrowPkg =
    if pkgsUnstable ? sparrow-wallet then pkgsUnstable.sparrow-wallet
    else if pkgsUnstable ? sparrow then pkgsUnstable.sparrow
    else throw "No sparrow package found in nixpkgs-unstable";

  sparrowExec = lib.getExe sparrowPkg;
in
{
  environment.systemPackages = [
    sparrowPkg
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

  systemd.tmpfiles.rules = lib.mkAfter [
    "d /home/user/Desktop 0755 user users - -"
    "L+ /home/user/Desktop/sparrow.desktop - - - - /etc/xdg/applications/sparrow.desktop"
  ];
}