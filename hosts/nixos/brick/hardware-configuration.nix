{
  lib,
  pkgs,
  config,
  modulesPath,
  ...
}:

let
  nvidiaPackage = config.hardware.nvidia.package;
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot = {
    # Low-latency kernel.
    kernelPackages = pkgs.linuxPackages_zen;
    initrd.availableKernelModules = [
      "xhci_pci"
      "ahci"
      "nvme"
      "usb_storage"
      "sd_mod"
    ];
    initrd.kernelModules = [ ];
    kernelModules = [
      "kvm-amd"
      "it87"
    ];
    extraModulePackages = [
      # https://github.com/NixOS/nixpkgs/pull/459648
      (pkgs.linuxPackages_zen.it87.overrideAttrs {
        version = "unstable-2025-10-06";
        src = pkgs.fetchFromGitHub {
          owner = "frankcrawford";
          repo = "it87";
          rev = "60d9def80d65e7e34a73e6f32d8677ad5bfa58a9";
          hash = "sha256-xlUyq1DQFBCvAs9DP6i1ose+6e+nmmXFRyuzRXCg+Ko=";
        };
      })
    ];
    kernelParams = [ "preempt=full" ];
  };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp5s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp4s0.useDHCP = lib.mkDefault true;

  hardware.bluetooth = {
    enable = true;
    settings = {
      General = {
        Privacy = "device";
        JustWorksRepairing = "always";
        Class = "0x000100";
        FastConnectable = "true";
      };
    };
  };
  hardware.xpadneo.enable = true;
  services.blueman.enable = true;

  hardware.nvidia.open = lib.mkOverride 990 (nvidiaPackage ? open && nvidiaPackage ? firmware);

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
