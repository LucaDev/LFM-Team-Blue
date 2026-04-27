{ config, lib, ... }:

let
  airgap = config.coldSigner.airgap.enable;
in
{
  networking.useDHCP = lib.mkIf airgap false;
  networking.networkmanager.enable = lib.mkForce (lib.mkIf airgap false);

  networking.useNetworkd = lib.mkIf airgap true;
  systemd.network.enable = lib.mkIf airgap true;

  services.openssh.enable = lib.mkIf airgap false;

  networking.firewall.enable = true;
}
