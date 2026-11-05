{
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./default.nix
    ./sd-image.nix
  ];

  image.baseName = "panda";

  panda.can.enable = true;
  panda.webcam.enable = true;

  # The PTY timing tests consistently time out in Nix build isolation on the Pi.
  home-manager.users.conroy.programs.direnv-instant.package =
    inputs.direnv-instant.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs
      {
        doCheck = false;
      };
  # Stylix's Home Manager module defines package overlays, so it needs its own
  # package set rather than Home Manager's global NixOS package set.
  home-manager.useGlobalPkgs = lib.mkForce false;

  console.enable = true;

  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [
    pkgs.raspberrypiWirelessFirmware
    pkgs.wireless-regdb
  ];

  boot.kernelPackages = pkgs.linuxPackagesFor (
    pkgs.callPackage ./kernel.nix {
      kernelPatches = with pkgs.kernelPatches; [
        bridge_stp_helper
        request_key_helper
      ];
    }
  );
  boot.consoleLogLevel = 7;
  # Keep the Raspberry Pi firmware-mutated DTB so config.txt overlays apply.
  boot.loader.generic-extlinux-compatible.useGenerationDeviceTree = false;
  boot.initrd.availableKernelModules = lib.mkForce [
    "ext4"
    "mmc_block"
  ];
  boot.supportedFilesystems = lib.mkForce [
    "ext4"
    "vfat"
  ];
  boot.kernelParams = lib.mkForce [
    "console=ttyS0,115200n8"
    "console=tty0"
    "earlycon=pl011,mmio32,0xfe201000"
    "ignore_loglevel"
    "loglevel=7"
    "lsm=landlock,yama,bpf"
  ];
  boot.kernelModules = [
    "brcmfmac"
    "brcmutil"
  ];
  boot.blacklistedKernelModules = [
    "bcm2835_v4l2"
  ];
}
