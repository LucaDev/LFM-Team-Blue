{ config, pkgs, lib, ... }:

let
  sparrowPkg =
    if pkgs ? sparrow-wallet then pkgs.sparrow-wallet
    else if pkgs ? sparrow then pkgs.sparrow
    else throw "No sparrow package found in this nixpkgs";

  sparrowReal = lib.getExe sparrowPkg;

  sparrowWrapped = pkgs.writeShellScriptBin "sparrow" ''
    export GDK_BACKEND=x11

    # Wichtig: nicht auf irgendeine systemweite Java-Installation zwingen
    unset JAVA_HOME
    unset CLASSPATH
    unset _JAVA_OPTIONS
    unset JAVA_TOOL_OPTIONS

    # VM/Proxmox/ohne GPU: JavaFX stabiler ohne OpenGL/ES2
    export _JAVA_OPTIONS="-Dprism.order=sw"

    exec ${sparrowReal} "$@"
  '';
in
{
  programs.dconf.enable = true;

  environment.systemPackages = with pkgs; [
    sparrowPkg
    sparrowWrapped

    # JavaFX/GTK Umfeld
    glib
    gtk3
    gsettings-desktop-schemas

    # Fonts + X11 Tools (häufig nötig)
    fontconfig
    dejavu_fonts
    xorg.xrandr
    xorg.xset

    # X11 libs, die JavaFX gelegentlich braucht
    xorg.libX11
    xorg.libXext
    xorg.libXi
    xorg.libXrender
    xorg.libXtst
    xorg.libXxf86vm
  ];

  environment.sessionVariables = {
    GDK_BACKEND = "x11";
  };

  environment.etc."xdg/applications/sparrow.desktop" = {
    mode = "0644";
    text = ''
      [Desktop Entry]
      Name=Sparrow Wallet
      Exec=${lib.getExe sparrowWrapped}
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