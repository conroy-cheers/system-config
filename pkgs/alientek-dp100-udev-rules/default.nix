{
  lib,
  writeText,
  stdenvNoCC,
  udevCheckHook,
}:

## Usage
# In NixOS, simply add this package to services.udev.packages:
#   services.udev.packages = [ pkgs.alientek-dp100-udev-rules ];

stdenvNoCC.mkDerivation {
  pname = "alientek-dp100-udev-rules";
  version = "0.1.0";

  src = writeText "99-atk-dp100.rules" ''
    # 2e3c:af01 ALIENTEK ATK-MDP100
    ATTRS{idVendor}=="2e3c", ATTRS{idProduct}=="af01", KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="660", GROUP="plugdev", TAG+="uaccess"
  '';

  nativeBuildInputs = [
    udevCheckHook
  ];

  doInstallCheck = true;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -D $src $out/lib/udev/rules.d/99-atk-dp100.rules
    runHook postInstall
  '';

  meta = {
    description = "udev rule for Alientek DP100";
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
