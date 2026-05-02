{
  description = "NixOS cold: stable base + Sparrow from nixos-unstable";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    pkgsUnstable = import nixpkgs-unstable { inherit system; };
  in
  {
    nixosConfigurations.cold = pkgs.lib.nixosSystem {
      inherit system;

      specialArgs = {
        inherit pkgsUnstable;
      };

      modules = [
        ./configuration.nix
      ];
    };
  };
}