{
  lib,
  writeText,
  stdenvNoCC,
  udevCheckHook,
}:

## Usage
# In NixOS, simply add this package to services.udev.packages:
#   services.udev.packages = [ pkgs.rpi-debug-probe-udev-rules ];

stdenvNoCC.mkDerivation {
  pname = "rpi-debug-probe-udev-rules";
  version = "0.1.0";

  src = writeText "50-picoprobe.rules" ''
    # https://github.com/raspberrypi/picoprobe
    # 2e8a:0004 Raspberry Pi picoprobe
    ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="0004", MODE:="660", GROUP="plugdev", TAG+="uaccess"
    # 2e8a:000c Raspberry Pi CMSIS-DAP
    ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="000c", MODE:="660", GROUP="plugdev", TAG+="uaccess"
  '';

  nativeBuildInputs = [
    udevCheckHook
  ];

  doInstallCheck = true;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -D $src $out/lib/udev/rules.d/50-picoprobe.rules
    runHook postInstall
  '';

  meta = {
    description = "pyOCD udev rule for Pi Debug Probe";
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
