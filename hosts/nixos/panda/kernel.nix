# Retain Panda's pinned 6.12 vendor recipe after Nixpkgs removed linux_rpi4.
# Adapted from nixpkgs ac6b2166e7a9375683b8e98f860f273222337b16,
# pkgs/os-specific/linux/kernel/linux-rpi.nix (MIT).
# nixos-hardware's current recipe targets 6.18 and cannot use this source unchanged.
{
  lib,
  fetchFromGitHub,
  buildLinux,
  kernelPatches,
  ...
}@args:
let
  modDirVersion = "6.12.75";
in
(buildLinux (
  args
  // {
    pname = "linux-rpi";
    version = "${modDirVersion}-1+rpt1";
    inherit modDirVersion;
    src = fetchFromGitHub {
      owner = "raspberrypi";
      repo = "linux";
      rev = "89050b1059997d38d55462b323b099a6436dc10d";
      hash = "sha256-qrljd20n4tj/7C7gzNnxw7JIyEF2Ppf1PWm2a7vxh1w=";
      # GitHub serves multiple archive variants for this commit.
      forceFetchGit = true;
    };
    defconfig = "bcm2711_defconfig";
    features = {
      efiBootStub = false;
    }
    // (args.features or { });
    isLTS = true;
    extraMeta = {
      platforms = with lib.platforms; lib.intersectLists (arm ++ aarch64) linux;
      hydraPlatforms = [ "aarch64-linux" ];
    };
    ignoreConfigErrors = true;
  }
  // (args.argsOverride or { })
)).overrideAttrs
  {
    postConfigure = ''
      sed -i $buildRoot/.config -e 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=""/'
      sed -i $buildRoot/include/config/auto.conf -e 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=""/'
    '';
    # Preserve the DTB aliases from the previous AArch64 recipe for U-Boot.
    postFixup = ''
      dtbDir=$out/dtbs/broadcom
      rm $dtbDir/bcm283*.dtb
      copyDTB() {
        cp -v "$dtbDir/$1" "$dtbDir/$2"
      }
      copyDTB bcm2710-rpi-zero-2.dtb bcm2837-rpi-zero-2.dtb
      copyDTB bcm2710-rpi-zero-2-w.dtb bcm2837-rpi-zero-2-w.dtb
      copyDTB bcm2710-rpi-3-b.dtb bcm2837-rpi-3-b.dtb
      copyDTB bcm2710-rpi-3-b-plus.dtb bcm2837-rpi-3-a-plus.dtb
      copyDTB bcm2710-rpi-3-b-plus.dtb bcm2837-rpi-3-b-plus.dtb
      copyDTB bcm2710-rpi-cm3.dtb bcm2837-rpi-cm3.dtb
      copyDTB bcm2711-rpi-4-b.dtb bcm2838-rpi-4-b.dtb
    '';
  }
