{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.development;
in
{
  config = lib.mkIf cfg.enable {
    virtualisation.vmVariant = {
      virtualisation = {
        host.pkgs = lib.mkDefault pkgs;
        cores = 4;
        memorySize = 8192;
        resolution = {
          x = 1280;
          y = 720;
        };
      };
    };
  };
}
