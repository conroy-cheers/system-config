{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.corncheese.desktop;
in
{
  options = {
    corncheese.desktop = {
      enable = lib.mkEnableOption "corncheese darwin desktop environment";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      programs._1password = {
        enable = true;
      };
      programs._1password-gui = {
        enable = true;
      };
    })
  ];
}
