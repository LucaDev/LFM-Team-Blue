{ config, pkgs, lib, ... }:

let
  # ============================
  # 1) Sparrow AppImage Quelle
  # ============================
  sparrowVersion = "1.9.1";

  sparrowAppImage = pkgs.fetchurl {
    url = "https://github.com/sparrowwallet/sparrow/releases/download/${sparrowVersion}/Sparrow-${sparrowVersion}-x86_64.AppImage";
    # 1) Beim ersten Build: lib.fakeSha256 einsetzen
    # 2) nixos-rebuild -> Hash aus Fehlermeldung kopieren und hier eintragen
    sha256 = lib.fakeSha256;
  };

  # ============================
  # 2) Launcher Script
  # ============================
  sparrowLauncher = pkgs.writeShellScriptBin "sparrow" ''
    set -euo pipefail
    export GDK_BACKEND=x11
    exec ${pkgs.appimage-run}/bin/appimage-run ${sparrowAppImage} "$@"
  '';

in
{
  # ============================
  # 3) System Pakete (Runtime)
  # ============================
  environment.systemPackages = with pkgs; [
    appimage-run
    sparrowLauncher

    # Fonts (JavaFX/GUI-Apps brauchen das praktisch immer)
    fontconfig
    dejavu_fonts

    # GTK/GLib Grundversorgung (hilft bei Dialogen/Theme)
    glib
    gtk3

    # X11 libs / Tools (VM + XFCE, stabilisiert Rendering)
    xorg.libX11
    xorg.libXext
    xorg.libXi
    xorg.libXrender
    xorg.libXtst
    xorg.libXxf86vm
    xorg.xrandr
    xorg.xset
  ];

  # Für XFCE sinnvoll (Portals/Settings). Schadet nicht.
  programs.dconf.enable = true;

  # Für manche VM-Setups hilfreich, sonst optional.
  environment.sessionVariables = {
    GDK_BACKEND = "x11";
  };

  # ============================
  # 4) Desktop Entry
  # ============================
  environment.etc."xdg/applications/sparrow.desktop" = {
    mode = "0644";
    text = ''
      [Desktop Entry]
      Name=Sparrow Wallet (AppImage)
      Exec=${lib.getExe sparrowLauncher}
      Type=Application
      Categories=Finance;
      Terminal=false
    '';
  };

  # ============================
  # 5) Optional: Desktop Shortcut
  # ============================
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /home/user/Desktop 0755 user users - -"
    "L+ /home/user/Desktop/sparrow.desktop - - - - /etc/xdg/applications/sparrow.desktop"
  ];

  # ============================
  # 6) Optional: Hardware Wallet udev rules
  # (nur falls du Ledger/Trezor nutzt)
  # ============================
  services.udev.packages = with pkgs; [
    ledger-udev-rules
    trezor-udev-rules
  ];
}