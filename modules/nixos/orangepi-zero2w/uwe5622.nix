{
  lib,
  stdenv,
  fetchFromGitHub,
  kernel,
  kernelModuleMakeFlags,
}:

stdenv.mkDerivation {
  pname = "uwe5622";
  version = "0-unstable-2026-09-13-${kernel.version}";

  src = fetchFromGitHub {
    owner = "armbian";
    repo = "uwe5622";
    rev = "cc2835a3f935d5297e03cdce464c1785381a7b4d";
    hash = "sha256-mrgY03APQsvqSRbSQVMU+H6+VlNvdHPvuB8lpDCn++8=";
  };

  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  enableParallelBuilding = true;

  postPatch = ''
    # Recurse into the BSP when building outside the kernel source tree.
    substituteInPlace Makefile \
      --replace-fail 'obj-y += unisocwcn/' 'obj-m += unisocwcn/' \
      --replace-fail '/lib/firmware/uwe5622/' '/run/current-system/firmware/'
    # Calibration and fallback firmware reads use filp_open, bypassing the
    # kernel firmware loader and its NixOS search path.
    substituteInPlace unisocwcn/platform/wcn_boot.c \
      --replace-fail '"/lib/firmware/"' '"/run/current-system/firmware/"'
    substituteInPlace unisocwifi/rf_marlin3.c \
      --replace-fail '"/lib/firmware"' '"/run/current-system/firmware/"'
  '';

  makeFlags = kernelModuleMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "M=$(NIX_BUILD_TOP)/source"
    "CONFIG_AW_WIFI_DEVICE_UWE5622=y"
    "CONFIG_WLAN_UWE5622=m"
    "CONFIG_TTY_OVERY_SDIO="
    "KCFLAGS=-DCONFIG_AW_BIND_VERIFY=1"
    "INSTALL_MOD_PATH=$(out)"
  ];
  buildFlags = [ "modules" ];
  installTargets = [ "modules_install" ];

  meta = {
    description = "UWE5622 SDIO Wi-Fi driver for Allwinner boards";
    homepage = "https://github.com/armbian/uwe5622";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
