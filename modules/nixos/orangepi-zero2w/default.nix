{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.orangePiZero2w;

  # The generic arm64 kernel installs every supported device tree in its main
  # output. Keep the one this board boots; hardware.deviceTree below applies
  # our overlay to a separate copy before the boot loader sees it.
  linuxOrangePiZero2W =
    (pkgs.linux_latest.override { ignoreConfigErrors = true; }).overrideAttrs
      (old: {
        postInstall = (old.postInstall or "") + ''
          target="$out/dtbs/allwinner/sun50i-h618-orangepi-zero2w.dtb"
          test -f "$target"
          find "$out/dtbs" -type f ! -path "$target" -delete
          find "$out/dtbs" -depth -type d -empty -delete
        '';
      });

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
      initrd = {
        includeDefaultModules = false;
        availableKernelModules = lib.mkForce [
          "sunxi-mmc"
          "mmc_block"
          "ext4"
        ];
      };
      # The generic kernel config requests sub-options for the hardware below;
      # allow those requests to disappear when their parent drivers are off.
      kernelPackages = lib.mkDefault (pkgs.linuxPackagesFor linuxOrangePiZero2W);
      kernelPatches = [
        {
          name = "mmc-pwrseq-simple-fallback-on-unsupported-reset-gpio";
          patch = ./pwrseq-simple-gpio-fallback.patch;
          # This headless H618 board has no PCI, VM, audio, or media devices.
          # Omitting debug information keeps its kernel build within the native
          # Linux builder's /build tmpfs.
          structuredExtraConfig =
            (lib.genAttrs [
              "ATA"
              "BT"
              "CAN"
              "CIFS"
              "DEBUG_INFO"
              "DEBUG_INFO_BTF"
              "DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT"
              "DRM"
              "HYPERV"
              "IIO"
              "INFINIBAND"
              "KVM"
              "MEDIA_SUPPORT"
              "NET_DSA"
              # Case-colliding target and match modules cannot both be installed
              # on the Mac-backed Linux builder filesystem.
              "NETFILTER_XT_TARGET_DSCP"
              "NETFILTER_XT_TARGET_HL"
              "NETFILTER_XT_TARGET_TCPMSS"
              "NETFILTER_XT_MATCH_RATEEST"
              "NFS_FS"
              "NVME_CORE"
              "PCI"
              "RUST"
              "SMC"
              "SOUND"
              "STAGING"
              "WWAN"
              "XEN"
            ] (_: lib.mkForce lib.kernel.no))
            // {
              DEBUG_INFO_NONE = lib.mkForce lib.kernel.yes;
            };
        }
      ];
      extraModulePackages = [
        (config.boot.kernelPackages.callPackage ./uwe5622.nix { })
      ];
      kernelModules = [
        "sun50i-cpufreq-nvmem"
        "sprdwl_ng"
      ];
      kernelParams = [
        "earlycon"
        "console=ttyS0,115200n8"
      ];
    };

    hardware.enableAllHardware = lib.mkForce false;
    hardware.firmware = [ (pkgs.callPackage ./firmware.nix { }) ];

    hardware.deviceTree = {
      enable = true;
      filter = "sun50i-h618-orangepi-zero2w.dtb";
      name = "allwinner/sun50i-h618-orangepi-zero2w.dtb";
      overlays = [
        {
          name = "orangepi-zero2w-wifi";
          filter = "sun50i-h618-orangepi-zero2w.dtb";
          dtsFile = ./wifi.dts;
        }
        {
          name = "orangepi-zero2w-cpufreq";
          filter = "sun50i-h618-orangepi-zero2w.dtb";
          dtsFile = ./cpufreq.dts;
        }
      ];
    };

    zramSwap = {
      enable = lib.mkDefault true;
      memoryPercent = lib.mkDefault 40;
    };

    system.build.orangepiZero2wUboot = ubootOrangePiZero2W;
  };
}
