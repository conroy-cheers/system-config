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

  console.enable = true;

  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [
    pkgs.raspberrypiWirelessFirmware
    pkgs.wireless-regdb
  ];

  boot.kernelPackages =
    let
      # GitHub serves multiple archive variants for this commit, so fetch the
      # Git tree directly to keep the source deterministic.
      kernel = pkgs.linuxPackages_rpi4.kernel.override {
        argsOverride.src = pkgs.fetchFromGitHub {
          owner = "raspberrypi";
          repo = "linux";
          rev = "89050b1059997d38d55462b323b099a6436dc10d";
          hash = "sha256-qrljd20n4tj/7C7gzNnxw7JIyEF2Ppf1PWm2a7vxh1w=";
          forceFetchGit = true;
        };
      };
    in
    pkgs.linuxPackagesFor kernel;
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
