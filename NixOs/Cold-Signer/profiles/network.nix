{ config, lib, ... }:

let
  airgap = config.airgap.enable;
in
{
  networking.useDHCP = lib.mkIf airgap false;
  networking.networkmanager.enable = lib.mkIf (!airgap) true;

  networking.useNetworkd = lib.mkIf airgap true;
  systemd.network.enable = lib.mkIf airgap true;

  services.openssh.enable = lib.mkIf airgap false;

  networking.firewall.enable = true;
}
