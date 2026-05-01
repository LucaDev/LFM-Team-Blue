{ config, pkgs, lib, ... }:

let
  sparrowPkg =
    if pkgs ? sparrow-wallet then pkgs.sparrow-wallet
    else if pkgs ? sparrow then pkgs.sparrow
    else throw "No sparrow package found in this nixpkgs";

  sparrowReal = lib.getExe sparrowPkg;

  sparrowWrapped = pkgs.writeShellScriptBin "sparrow" ''
    export GDK_BACKEND=x11
    export JAVA_HOME=${pkgs.jre17}
    export PATH=${pkgs.jre17}/bin:$PATH

    unset _JAVA_OPTIONS
    unset JAVA_TOOL_OPTIONS
    unset CLASSPATH

    # Optional: hilft in VMs/ohne saubere GL-Unterstützung
    export _JAVA_OPTIONS="-Dprism.order=sw -Djavafx.platform=gtk"

    exec ${sparrowReal} "$@"
  '';
in
{
  environment.systemPackages = with pkgs; [
    sparrowPkg
    sparrowWrapped

    # Java Runtime (definiert)
    jre17

    # JavaFX/GUI-Umfeld, sehr oft nötig in NixOS/VMs
    fontconfig
    dejavu_fonts
    glib
    gtk3

    # X11 Tools/Libs, JavaFX fragt teils xrandr/xset ab
    xorg.xrandr
    xorg.xset

    xterm
  ];

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