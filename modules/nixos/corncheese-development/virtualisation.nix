{ lib, config, ... }:

let
  cfg = config.corncheese.development;
in
{
  config = lib.mkIf cfg.enable {
    virtualisation.vmVariant = {
      virtualisation = {
        host.pkgs = import <nixpkgs> { };
        cores = 4;
        memorySize = 8192;
        resolution = { x = 1280; y = 720; };
      };
    };
  };
}
