{ config, pkgs, lib, ... }:

{
  imports = [
    ./profiles/airgap-option.nix
    ./profiles/hardware-vm.nix
    ./hardware-configuration.nix
    ./profiles/base.nix
    ./profiles/gui.nix
    ./profiles/sparrow.nix
    ./profiles/network.nix
  ];

  nix.settings.download-buffer-size = 268435456; # 256MB

  security.lockKernelModules = true;
  boot.blacklistedKernelModules = [
    "firewire-core"
    "bluetooth"
  ];

  # HARDENING

  services.openssh.enable = false;

  #Kernel
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "kernel.randomize_va_space" = 2;
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.default.disable_ipv6" = 1;
    "net.ipv4.conf.all.route_localnet" = 0;
  };

  systemd.coredump.enable = false;

  # volatile logs (no disk persistence)
  services.journald.extraConfig = ''
    Storage=volatile
    Compress=yes
  '';

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.editor = false;
  boot.loader.efi.canTouchEfiVariables = true;

  airgap.enable = true;

  specialisation.online.configuration = {
    airgap.enable = lib.mkForce false;
  };

  cold.sparrowNetwork = "regtest";

  system.stateVersion = "24.05";
}