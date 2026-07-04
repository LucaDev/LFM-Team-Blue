{
  description = "NixOS cold: stable";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
  let
    system = "x86_64-linux";
  in
  {
    nixosConfigurations.cold = nixpkgs.lib.nixosSystem {
      inherit system;

      modules = [
        ./configuration.nix
      ];
    };
  };
}