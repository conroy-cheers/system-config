{
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

  panda.can.enable = false;
  panda.webcam.enable = true;

  console.enable = true;

  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [
    pkgs.raspberrypiWirelessFirmware
    pkgs.wireless-regdb
  ];

  boot.kernelPackages = pkgs.linuxPackages_rpi4;
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
