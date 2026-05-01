{ config, pkgs, ... }:

let
  sparrowPkg =
    if pkgs ? sparrow-wallet then pkgs.sparrow-wallet
    else if pkgs ? sparrow then pkgs.sparrow
    else throw "No sparrow package found in this nixpkgs";
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
      Exec=${sparrowPkg}/bin/sparrow
      Type=Application
      Categories=Finance;
      Terminal=false
    '';
  };
}