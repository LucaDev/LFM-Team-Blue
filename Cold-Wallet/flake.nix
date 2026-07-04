{
  description = "NixOS cold: stable";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    #nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    #pkgsUnstable = import nixpkgs-unstable { inherit system; };
  in
  {
    nixosConfigurations.cold = nixpkgs.lib.nixosSystem {
      inherit system;

      #specialArgs = {
      #  inherit pkgsUnstable;
      #};

      modules = [
        ./configuration.nix
      ];
    };
  };
}