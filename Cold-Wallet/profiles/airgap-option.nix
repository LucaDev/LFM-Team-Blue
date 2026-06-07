{ lib, ... }:

{
  options.airgap.enable = lib.mkEnableOption "Air-gap mode (disable networking + SSH)";

  config = { };
}