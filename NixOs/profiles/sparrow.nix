{ config, pkgs, lib, ... }:

{
  # GSettings / dconf
  programs.dconf.enable = true;

  # Flatpak aktivieren
  services.flatpak.enable = true;

  environment.systemPackages = with pkgs; [
    flatpak
  ];

  # XDG Portals → GTK (richtig für XFCE)
  xdg.portal.enable = true;
  xdg.portal.extraPortals = with pkgs; [
    xdg-desktop-portal-gtk
  ];

  # Optional, aber sinnvoll in VMs
  environment.sessionVariables = {
    GDK_BACKEND = "x11";
  };

  # Desktop-Eintrag für Sparrow Flatpak
  environment.etc."xdg/applications/sparrow-flatpak.desktop" = {
    mode = "0644";
    text = ''
      [Desktop Entry]
      Name=Sparrow Wallet (Flatpak)
      Exec=flatpak run com.sparrowwallet.Sparrow
      Type=Application
      Categories=Finance;
      Terminal=false
    '';
  };

  # Desktop-Shortcut erzeugen
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /home/user/Desktop 0755 user users - -"
    "L+ /home/user/Desktop/sparrow.desktop - - - - /etc/xdg/applications/sparrow-flatpak.desktop"
  ];
}