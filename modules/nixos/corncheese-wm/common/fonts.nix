{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.wm;
  themeDetails = config.corncheese.theming.themeDetails;
in
{
  config = lib.mkIf cfg.enable {
    fonts.packages = with pkgs; [ themeDetails.fontPkg ];
  };
}
