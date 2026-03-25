{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.orangePiZero2w;

  # Adapted from katyo/nixos-arm's sunxi/Orange Pi support, but updated to use
  # the current kernel and U-Boot sources already pinned by this flake.
  ubootOrangePiZero2W = pkgs.buildUBoot {
    defconfig = "orangepi_zero2w_defconfig";
    extraMeta.platforms = [ "aarch64-linux" ];
    env.BL31 = "${pkgs.armTrustedFirmwareAllwinnerH616}/bl31.bin";
    filesToInstall = [ "u-boot-sunxi-with-spl.bin" ];
  };
in
{
  options.hardware.orangePiZero2w.enable = lib.mkEnableOption "Orange Pi Zero 2W board support";

  config = lib.mkIf cfg.enable {
    boot = {
      loader = {
        grub.enable = false;
        generic-extlinux-compatible.enable = true;
      };

      consoleLogLevel = lib.mkDefault 7;
      initrd.availableKernelModules = [ "sunxi-mmc" ];
      kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
      kernelParams = [
        "earlycon"
        "console=ttyS0,115200n8"
      ];
    };

    hardware.deviceTree = {
      enable = true;
      name = "allwinner/sun50i-h618-orangepi-zero2w.dtb";
    };

    zramSwap = {
      enable = lib.mkDefault true;
      memoryPercent = lib.mkDefault 40;
    };

    system.build.orangepiZero2wUboot = ubootOrangePiZero2W;
  };
}
