{ config, lib, ... }:

let
  airgap = config.airgap.enable;
  iface = "ens18";
in
{
  config = lib.mkIf airgap {

    networking.useDHCP = false;
    networking.interfaces.${iface}.useDHCP = false;

    networking.networkmanager.enable = false;
    networking.useNetworkd = true;
    systemd.network.enable = true;

    networking.defaultGateway = null;
    networking.defaultGateway6 = null;

    networking.enableIPv6 = false;

    services.openssh.enable = false;

    networking.firewall.enable = true;

    boot.kernel.sysctl = {
      "net.ipv6.conf.${iface}.disable_ipv6" = 1;
      "net.ipv6.conf.${iface}.accept_ra" = 0;
      "net.ipv6.conf.${iface}.autoconf" = 0;
      "net.ipv6.conf.${iface}.accept_redirects" = 0;
      "net.ipv6.conf.${iface}.dad_transmits" = 0;

      "net.ipv4.conf.${iface}.disable_ipv4" = 1;
      "net.ipv4.ip_forward" = 0;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
    };
  };
}