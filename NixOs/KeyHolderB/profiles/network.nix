{ config, pkgs, lib, ... }:

{
  # Kein DHCP, kein NetworkManager
  networking.useDHCP = false;
  networking.networkmanager.enable = lib.mkForce false;

  # SSH aus (Cold)
  services.openssh.enable = false;

  networking.useNetworkd = true;
  systemd.network.enable = true;

  # Firewall kann an bleiben (praktisch “egal” ohne Netz, aber sauber)
  networking.firewall.enable = true;
}
