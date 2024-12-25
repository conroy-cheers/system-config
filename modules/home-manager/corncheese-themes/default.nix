{ pkgs, lib, config, ... }:
let
  cfg = config.corncheese.theming;
  themeDetails = import (../../common + "/themes/${cfg.theme}.nix") { inherit pkgs; };
in
{
  options = {
    corncheese.theming = {
      enable = lib.mkEnableOption "corncheese theming";
      theme = lib.mkOption {
        type = with lib.types; str;
        description = "Theme to use";
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
      base16Scheme = lib.mkIf (cfg.theme != null)
        "${pkgs.base16-schemes}/share/themes/${themeDetails.base16Scheme}.yaml";
      override = lib.mkIf (cfg.themeDetails.stylixOverride != null) cfg.themeDetails.stylixOverride;
      opacity = {
        terminal = cfg.themeDetails.opacity;
        applications = cfg.themeDetails.opacity;
        desktop = cfg.themeDetails.opacity;
        popups = cfg.themeDetails.opacity;
      };
      fonts = {
        sizes = {
          terminal = 11;
        };
      };

      targets.nixvim.enable =
        lib.mkIf (cfg.theme != null) false;

      # targets.btop.enable =
      #   lib.mkIf (settings.themecfg.themeDetails.btopTheme != null) false;
    };
  };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
