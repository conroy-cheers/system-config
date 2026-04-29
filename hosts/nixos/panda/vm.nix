{
  config,
  pkgs,
  ...
}:
let
  klipperStubBin = pkgs.writeShellApplication {
    name = "klippy";
    text = ''
      printf '%s\n' "$*" > /run/klipper/stub-args
      exec ${pkgs.coreutils}/bin/sleep infinity
    '';
  };

  klipperStub = pkgs.symlinkJoin {
    name = "klipper-stub";
    paths = [ pkgs.klipper ];
    postBuild = ''
      ln -sf ${klipperStubBin}/bin/klippy $out/bin/klippy
    '';
    passthru = pkgs.klipper.passthru // {
      src = pkgs.klipper.src;
    };
  };

  moonrakerStub = pkgs.writeShellApplication {
    name = "moonraker";
    text = ''
      printf '%s\n' "$*" > ${config.services.moonraker.stateDir}/stub-args
      exec ${pkgs.coreutils}/bin/sleep infinity
    '';
  };
in
{
  panda.can.enable = true;
  panda.mockCan = true;
  panda.wifiSecretsFile = pkgs.writeText "panda-wifi.env" ''
    pass_home="york micro speckle"
    pass_abi="abi_humanoid"
  '';

  networking.useDHCP = false;
  networking.interfaces.eth1.useDHCP = true;

  services.klipper.package = klipperStub;
  services.moonraker.package = moonrakerStub;

  virtualisation.vmVariant.virtualisation = {
    memorySize = 2048;
    cores = 2;
  };
}
