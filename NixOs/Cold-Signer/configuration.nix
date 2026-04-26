{ config, pkgs, ... }:

{
  imports = [    
    ./hardware-configuration.nix
    ./profiles/base.nix
    ./profiles/gui.nix
    ./profiles/sparrow.nix
    ./profiles/network.nix
  ];

}