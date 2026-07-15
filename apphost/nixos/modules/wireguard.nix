{ config, pkgs, ... }:

{
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.10.0.2/24" ];
    listenPort = 51820;

    privateKeyFile = "/var/lib/wireguard/private.key";
    generatePrivateKeyFile = true;
  };
}
