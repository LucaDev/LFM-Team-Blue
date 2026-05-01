{ config, pkgs, lib, ... }:

let
  sparrowPkg =
    if pkgs ? sparrow-wallet then pkgs.sparrow-wallet
    else if pkgs ? sparrow then pkgs.sparrow
    else throw "No sparrow package found in this nixpkgs";

  sparrowReal = lib.getExe sparrowPkg;

  javaPkg =
    if pkgs ? jre17 then pkgs.jre17
    else if pkgs ? jdk17 then pkgs.jdk17
    else if pkgs ? openjdk17 then pkgs.openjdk17
    else if pkgs ? "temurin-jre-bin-17" then pkgs."temurin-jre-bin-17"
    else if pkgs ? "temurin-bin-17" then pkgs."temurin-bin-17"
    else if pkgs ? jre then pkgs.jre
    else if pkgs ? jdk then pkgs.jdk
    else throw "No Java runtime found in this nixpkgs (tried jre17/jdk17/openjdk17/temurin*/jre/jdk)";

  sparrowWrapped = pkgs.writeShellScriptBin "sparrow" ''
    export GDK_BACKEND=x11
    export JAVA_HOME=${javaPkg}
    export PATH=${javaPkg}/bin:$PATH

    unset _JAVA_OPTIONS
    unset JAVA_TOOL_OPTIONS
    unset CLASSPATH

    # Sehr oft hilfreich in VMs (Proxmox) oder ohne gutes OpenGL:
    export _JAVA_OPTIONS="-Dprism.order=sw -Djavafx.platform=gtk"

    exec ${sparrowReal} "$@"
  '';
in
{
  environment.systemPackages = with pkgs; [
    sparrowPkg
    sparrowWrapped

    # GUI/JavaFX-Umfeld, verhindert viele JavaFX-Crashes:
    fontconfig
    dejavu_fonts
    glib
    gtk3
    xorg.xrandr
    xorg.xset
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
}