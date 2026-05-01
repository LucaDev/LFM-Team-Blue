{ config, pkgs, lib, ... }:

let
  sparrowDir = "/opt/sparrow/Sparrow";

  sparrowLauncher = pkgs.writeShellScriptBin "sparrow" ''
    set -e
    export GDK_BACKEND=x11
    exec ${sparrowDir}/sparrow "$@"
  '';
in
{
  environment.systemPackages = with pkgs; [
    sparrowLauncher

    # Minimal notwendige Runtime-Libs für XFCE / GUI
    fontconfig
    dejavu_fonts
    glib
    gtk3

    xorg.libX11
    xorg.libXext
    xorg.libXi
    xorg.libXrender
    xorg.libXtst
    xorg.libXxf86vm
    xorg.xrandr
    xorg.xset
  ];

  programs.dconf.enable = true;

  environment.sessionVariables = {
    GDK_BACKEND = "x11";
  };

  environment.etc."xdg/applications/sparrow.desktop" = {
    mode = "0644";
    text = ''
      [Desktop Entry]
      Name=Sparrow Wallet
      Exec=${lib.getExe sparrowLauncher}
      Type=Application
      Categories=Finance;
      Terminal=false
    '';
  };
}