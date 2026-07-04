{ pkgs, lib, pkgsUnstable, config, ... }:

let
  sparrowPkg =
    if pkgsUnstable ? sparrow-wallet then pkgsUnstable.sparrow-wallet
    else if pkgsUnstable ? sparrow then pkgsUnstable.sparrow
    else throw "No sparrow package found in nixpkgs-unstable";
  sparrowExec = lib.getExe sparrowPkg;
in
{
  options.cold.sparrowNetwork = lib.mkOption {
    type = lib.types.enum [ "regtest" "testnet" "mainnet" ];
    default = "regtest";
    description = "Bitcoin-Netz, mit dem Sparrow startet.";
  };

  config = {
    environment.systemPackages = [ sparrowPkg ];

    environment.etc."xdg/applications/sparrow.desktop" = {
      mode = "0644";
      text = ''
        [Desktop Entry]
        Name=Sparrow Wallet
        Exec=${sparrowExec} --network ${config.cold.sparrowNetwork}
        Type=Application
        Categories=Finance;
        Terminal=false
      '';
    };

    systemd.tmpfiles.rules = lib.mkAfter [
      "L+ /home/user/Desktop/sparrow.desktop - - - - /etc/xdg/applications/sparrow.desktop"
    ];
  };
}