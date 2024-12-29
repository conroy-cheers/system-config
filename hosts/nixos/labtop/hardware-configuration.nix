{ lib, pkgs, config, modulesPath, ... }:

let
  nvidiaPackage = config.hardware.nvidia.package;
in
{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot = {
    initrd = {
      availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" ];
    };
    kernelModules = [ "kvm-amd" ];
    kernelParams = [
      "mem_sleep_default=deep"
      "pcie_aspm.policy=powersupersave"
    ];
    blacklistedKernelModules = [ "nouveau" ];
  };

  hardware.nvidia.prime = {
    # Bus ID of the AMD GPU.
    amdgpuBusId = lib.mkDefault "PCI:63:0:0";

    # Bus ID of the NVIDIA GPU.
    nvidiaBusId = lib.mkDefault "PCI:1:0:0";
  };
  hardware.nvidia.open = lib.mkOverride 990 (nvidiaPackage ? open && nvidiaPackage ? firmware);

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp5s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp4s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
