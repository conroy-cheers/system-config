{ runCommand, fetchurl }:
let
  base = "https://raw.githubusercontent.com/armbian/firmware/2a9e1c19460401443267926181191d57e3ff175d/uwe5622";
  modem = fetchurl {
    url = "${base}/wcnmodem.bin";
    hash = "sha256-EZuHzjCHVzSmdGL3KT+4/oWs8ycP6LeMl4riS+dxWoA=";
  };
  calibration = fetchurl {
    url = "${base}/wifi_2355b001_1ant.ini";
    hash = "sha256-HzxA7CRajQuZrRwjcGWX1t1QCKuAzvt7zBlW78TpOPc=";
  };
in
runCommand "uwe5622-firmware"
  {
    # The vendor driver reads calibration and fallback firmware with filp_open,
    # which cannot use the kernel firmware loader's decompression support.
    passthru.compressFirmware = false;
  }
  ''
    install -Dm644 ${modem} $out/lib/firmware/wcnmodem.bin
    install -Dm644 ${calibration} $out/lib/firmware/wifi_2355b001_1ant.ini
  ''
