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
    "kernel.randomize_va_space" = 2;    
    "kernel.kptr_restrict"              = 2;   # Kernel-Pointer verstecken
    "kernel.dmesg_restrict"             = 1;   # dmesg nur für root
    "kernel.yama.ptrace_scope"          = 2;   # ptrace stark einschränken
    "kernel.unprivileged_bpf_disabled"  = 1;
    "net.core.bpf_jit_harden"           = 2;

    #IP-Härtung
      "net.ipv6.conf.all.disable_ipv6"         = 1;
      "net.ipv6.conf.default.disable_ipv6"     = 1;

      "net.ipv4.ip_forward"                    = 0;
      "net.ipv4.conf.all.route_localnet" = 0;
      "net.ipv4.conf.all.accept_redirects"     = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.send_redirects"       = 0;
      "net.ipv4.conf.default.send_redirects"   = 0;
      "net.ipv4.conf.all.accept_source_route"  = 0;
      "net.ipv4.conf.all.rp_filter"            = 1;
  };
  security.protectKernelImage = true;

  systemd.coredump.enable = false;

  # volatile logs (no disk persistence)
  services.journald.extraConfig = ''
    Storage=volatile
    Compress=yes
    RuntimeMaxUse=150M
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