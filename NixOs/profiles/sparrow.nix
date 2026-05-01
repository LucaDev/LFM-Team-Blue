{ config, pkgs, lib, ... }:

let
  sparrowPkg =
    if pkgs ? sparrow-wallet then pkgs.sparrow-wallet
    else if pkgs ? sparrow then pkgs.sparrow
    else throw "No sparrow package found in this nixpkgs";

  sparrowReal = lib.getExe sparrowPkg;

  # Java 17 mit JavaFX
  jdkWithFX =
    (pkgs.openjdk17.override { enableJavaFX = true; });

  sparrowWrapped = pkgs.writeShellScriptBin "sparrow" ''
    export GDK_BACKEND=x11
    export JAVA_HOME=${jdkWithFX}
    export PATH=${jdkWithFX}/bin:$PATH

    unset _JAVA_OPTIONS
    unset JAVA_TOOL_OPTIONS
    unset CLASSPATH

    # VM/Proxmox häufig nötig:
    export _JAVA_OPTIONS="-Dprism.order=sw"

    exec ${sparrowReal} "$@"
  '';
in
{
  environment.systemPackages = with pkgs; [
    sparrowPkg
    sparrowWrapped

    fontconfig
    dejavu_fonts
    xorg.xrandr
    xorg.xset
    glib
    gtk3
    gsettings-desktop-schemas
  ];

  programs.dconf.enable = true;

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