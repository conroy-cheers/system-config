{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.corncheese.theming;
  themeDetails = lib.recursiveUpdate (import (../../common + "/themes/${cfg.theme}.nix") {
    inherit pkgs;
  }) cfg.themeOverrides;
in
{
  options = {
    corncheese.theming = {
      enable = lib.mkEnableOption "corncheese theming";
      theme = lib.mkOption {
        type = with lib.types; str;
        description = "Theme to use";
      };
      themeOverrides = lib.mkOption {
        type = with lib.types; anything;
        description = "Overrides for imported theme data";
        default = { };
      };
      themeDetails = lib.mkOption {
        type = with lib.types; anything;
        description = "Imported theme data";
        readOnly = true;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    corncheese.theming.themeDetails = themeDetails;

    stylix = {
      enable = true;
      polarity = "dark";
      image = themeDetails.wallpaper;
      base16Scheme = lib.mkIf (
        cfg.theme != null
      ) "${pkgs.base16-schemes}/share/themes/${themeDetails.base16Scheme}.yaml";
      override = lib.mkIf (themeDetails.stylixOverride != null) themeDetails.stylixOverride;
      opacity = {
        terminal = themeDetails.opacity;
        applications = themeDetails.opacity;
        desktop = themeDetails.opacity;
        popups = themeDetails.opacity;
      };
      fonts = {
        sizes = {
          terminal = themeDetails.fontSize;
        };
      };

      targets.nixvim.enable = lib.mkIf (cfg.theme != null) false;

      targets.vscode.profileNames = [ "default" ];
      targets.firefox.profileNames = [ "default" ];
    };
  };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
