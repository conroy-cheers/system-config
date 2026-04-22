{
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./default.nix
    ./sd-image.nix
    "${inputs.hardware}/raspberry-pi/4"
  ];

  image.baseName = "panda";

  console.enable = false;

  hardware.raspberry-pi."4" = {
    apply-overlays-dtmerge.enable = lib.mkForce false;
  };

  hardware.deviceTree = {
    enable = true;
    filter = lib.mkForce null;
    overlays = [
      {
        name = "disable-bt";
        filter = "bcm2711-rpi-4*.dtb";
        dtboFile = "${pkgs.raspberrypifw}/share/raspberrypi/boot/overlays/disable-bt.dtbo";
      }
    ];
  };

  hardware.enableRedistributableFirmware = lib.mkForce false;
  hardware.firmware = [
    pkgs.raspberrypiWirelessFirmware
    pkgs.wireless-regdb
  ];

  boot.kernelPackages = pkgs.linuxPackages_rpi4;
  boot.consoleLogLevel = 7;
  boot.initrd.availableKernelModules = [
    "bcm2835-sdhost"
    "mmc_block"
  ];
  boot.kernelParams = lib.mkForce [
    "console=ttyAMA0,115200n8"
    "earlycon=pl011,mmio32,0xfe201000"
    "ignore_loglevel"
    "loglevel=7"
    "lsm=landlock,yama,bpf"
  ];
  boot.supportedFilesystems = lib.mkForce [
    "ext4"
    "vfat"
  ];
  boot.kernelModules = [
    "brcmfmac"
    "brcmutil"
  ];
}
