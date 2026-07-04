{ config, lib, pkgs, ... }:

let
  airgap = config.airgap.enable;
in
{
  config = lib.mkIf airgap {

    # --- keine Netzkonfiguration hochziehen ---
    networking.useDHCP = false;
    networking.networkmanager.enable = false;
    networking.enableIPv6 = false;
    networking.useNetworkd = true;
    systemd.network.enable = true;
    systemd.network.wait-online.enable = false;

    networking.defaultGateway = null;
    networking.defaultGateway6 = null;

    services.openssh.enable = false;

        # --- Firewall auf nftables-Basis ---
    networking.nftables.enable = true;

    # Eingehend: NixOS-Firewall (default deny), keine offenen Ports
    networking.firewall.enable = true;
    networking.firewall.allowedTCPPorts = [ ];
    networking.firewall.allowedUDPPorts = [ ];

    # Ausgehend: alles droppen, nur loopback erlaubt
    networking.nftables.tables.airgap-egress = {
      family = "inet";
      content = ''
        chain output {
          type filter hook output priority 0; policy drop;
          oifname "lo" accept
        }
      '';
    };

    # --- alle Nicht-Loopback-Interfaces beim Boot hart down + Adressen leeren ---
    systemd.services.airgap-down-links = {
      description = "Airgap: bring all non-loopback links down";
      wantedBy = [ "multi-user.target" ];
      after    = [ "network-pre.target" ];
      before   = [ "network.target" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      path = [ pkgs.iproute2 ];
      script = ''
        set -euo pipefail
        for i in $(ls /sys/class/net); do
          [ "$i" = "lo" ] && continue
          ip link set "$i" down
          ip addr flush dev "$i"
        done
      '';
    };
  };
}