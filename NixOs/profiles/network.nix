{ config, lib, pkgs, ... }:

let
  airgap = config.airgap.enable;

in
{
  config = lib.mkIf airgap {

    networking.useDHCP = false;

    networking.networkmanager.enable = false;
    networking.useNetworkd = true;
    systemd.network.enable = true;

    networking.defaultGateway = null;
    networking.defaultGateway6 = null;

    networking.enableIPv6 = false;

    services.openssh.enable = false;

    networking.firewall.enable = true;

    # kein Warten auf Netzwerk
    systemd.network.wait-online.enable = false;

    
    # One-shot: bei jedem boot/switch alle aktuellen Interfaces härten
    systemd.services.airgap-harden-interfaces = {
      description = "Airgap: harden all current network interfaces";
      wantedBy = [ "multi-user.target" ];
      after = [ "sysinit.target" ];
      serviceConfig = { Type = "oneshot"; };
      path = [ pkgs.procps pkgs.iproute2 pkgs.bash ];
      script = ''
        set -euo pipefail
        for i in $(ip -o link show | awk -F': ' '{print $2}'); do
          [ "$i" = "lo" ] && continue

          sysctl -w "net.ipv6.conf.$i.disable_ipv6=1" >/dev/null || true
          sysctl -w "net.ipv6.conf.$i.accept_ra=0" >/dev/null || true
          sysctl -w "net.ipv6.conf.$i.autoconf=0" >/dev/null || true
          sysctl -w "net.ipv6.conf.$i.accept_redirects=0" >/dev/null || true
          sysctl -w "net.ipv6.conf.$i.dad_transmits=0" >/dev/null || true

          sysctl -w "net.ipv4.conf.$i.disable_ipv4=1" >/dev/null || true
          sysctl -w "networking.interfaces.$i.useDHCP=1;" >/dev/null || true
        done
      '';
    };


    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 0;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
    };
  };
}