{
  inputs,
  config,
  lib,
  pkgs,
  meta,
  ...
}:

let
  cfg = config.corncheese.macos;
in
{
  options = {
    corncheese.macos = {
      enable = lib.mkEnableOption "corncheese macOS-specific home-manager config";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; builtins.concatLists [ [ betterdisplay ] ];
  };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
