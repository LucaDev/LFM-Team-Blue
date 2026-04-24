{ config, pkgs, ... }:

{
  # Kein DHCP, kein NetworkManager
  networking.useDHCP = false;
  networking.networkmanager.enable = false;

  # SSH aus (Cold)
  services.openssh.enable = false;

  # Firewall kann an bleiben (praktisch “egal” ohne Netz, aber sauber)
  networking.firewall.enable = true;
}
