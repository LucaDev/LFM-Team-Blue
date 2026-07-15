{ config, pkgs, ... }:

{
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.10.0.2/24" ];
    listenPort = 51820;

    privateKeyFile = "/var/lib/wireguard/private.key";
    generatePrivateKeyFile = true;

    postSetup = ''
        PEER_FILE="/var/lib/wireguard/signer.json"
        if [ -f "$PEER_FILE" ]; then
            PUBKEY=$(${pkgs.jq}/bin/jq -r '.signer_public_key' "$PEER_FILE")
            ALLOWED=$(${pkgs.jq}/bin/jq -r '.allowed_ips_signer' "$PEER_FILE")
            ENDPOINT=$(${pkgs.jq}/bin/jq -r '.endpoint' "$PEER_FILE")

            ${pkgs.wireguard-tools}/bin/wg set wg0 \
                peer "$PUBKEY" \
                allowed-ips "$ALLOWED" \
                endpoint "$ENDPOINT" \
                persistent-keepalive 25
        fi
    '';
  };
}
