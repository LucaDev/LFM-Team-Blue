{ config, lib, ... }:

let
  airgap = config.airgap.enable;
in
{
  networking.useDHCP = lib.mkIf airgap false;
  networking.networkmanager.enable = lib.mkIf airgap false;

  networking.useNetworkd = lib.mkIf airgap true;
  systemd.network.enable = lib.mkIf airgap true;

  networking.interfaces.ens18.useDHCP = lib.mkIf airgap false;
  networking.interfaces.ens18.ipv4.addresses = lib.mkIf airgap [ ];
  networking.interfaces.ens18.ipv6.addresses = lib.mkIf airgap [ ];

  services.openssh.enable = lib.mkIf airgap false;

  networking.firewall.enable = true;
}
