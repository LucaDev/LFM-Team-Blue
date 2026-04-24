{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    sparrow-wallet
    xterm
  ];

  environment.etc."xdg/applications/sparrow.desktop" = {
    mode = "0644";
    text =''
      [Desktop Entry]
      Name=Sparrow Wallet
      Exec=sparrow
      Type=Application
      Categories=Finance;
      Terminal=false
    '';
  };
}