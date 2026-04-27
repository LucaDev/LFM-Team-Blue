{ config, pkgs, lib, ... }:

{
  # Kein DHCP, kein NetworkManager
  
  networking.networkmanager.enable = lib.mkIf (!config.airgap) true;
  networking.useDHCP = lib.mkIf (!config.airgap) true;


  # SSH aus (Cold)
  services.openssh.enable = lib.mkIf (!config.airgap) true;

  networking.useNetworkd = lib.mkIf config.airgap true;
  systemd.network.enable = lib.mkIf config.airgap true;


  # Firewall kann an bleiben (praktisch “egal” ohne Netz, aber sauber)
  networking.firewall.enable = true;
}
