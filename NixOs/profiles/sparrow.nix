{ config, pkgs, lib, ... }:

let
  #====================#
  # 1) Sparrow Wrapper: startet Sparrow stabil in XFCE/Proxmox (X11 + optional Software Rendering)  # 1) Sparrow Standalone Pfad (liegt bereits im Repo /etc/nixos/...)
  #====================#
  sparrowWrapped = pkgs.writeShellScriptBin "sparrow" ''
    set -euo pipefail

    if [ ! -x "${sparrowStandalone}" ]; then
      echo "ERROR: Sparrow Standalone not executable or not found:"
      echo "  ${sparrowStandalone}"
      exit 1
    fi

    export GDK_BACKEND=x11

    unset JAVA_HOME
    unset CLASSPATH
    unset _JAVA_OPTIONS
    unset JAVA_TOOL_OPTIONS

    # Proxmox/VM: JavaFX stabiler ohne OpenGL/ES2
    export _JAVA_OPTIONS="-Dprism.order=sw"

    exec "${sparrowStandalone}" "$@"
  '';
in
{
  #====================#
  # 3) Runtime-Dependencies für JavaFX/GUI (XFCE)
  #====================#
  programs.dconf.enable = true;

  environment.sessionVariables = {
    GDK_BACKEND = "x11";
  };

  environment.systemPackages = with pkgs; [
    sparrowWrapped

    # Fonts / Fontconfig (JavaFX/GUI)
    fontconfig
    dejavu_fonts

    # GTK/GLib (Dialogs/Themes/Integration)
    glib
    gtk3
    gsettings-desktop-schemas

    # X11 libs / Tools (häufig erforderlich bei JavaFX in VMs)
    xorg.libX11
    xorg.libXext
    xorg.libXi
    xorg.libXrender
    xorg.libXtst
    xorg.libXxf86vm
    xorg.xrandr
    xorg.xset

    # Optional, falls Audio-Init Probleme auftauchen:
    # alsa-lib
  ];

  #====================#
  # 4) Desktop Entry (startet Wrapper, nicht direkt das Binary)
  #====================#
  environment.etc."xdg/applications/sparrow.desktop" = {
    mode = "0644";
    text = ''
      [Desktop Entry]
      Name=Sparrow Wallet (Standalone)
      Exec=${lib.getExe sparrowWrapped}
      Type=Application
      Categories=Finance;
      Terminal=false
    '';
  };

  #====================#
  # 5) Optional: Desktop-Shortcut (dein bisheriger Stil)
  #====================#
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /home/user/Desktop 0755 user users - -"
    "L+ /home/user/Desktop/sparrow.desktop - - - - /etc/xdg/applications/sparrow.desktop"
  ];

  #====================#
  # 6) Optional: Udev rules für Hardware Wallets (nur wenn benötigt)
  #====================#
  # services.udev.packages = with pkgs; [
  #   ledger-udev-rules
  #   trezor-udev-rules
  # ];
}
  #====================#
  sparrowStandalone = "/etc/nixos/NixOs/profiles/programs/Sparrow/bin/Sparrow";

  #====================#