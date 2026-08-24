{
  inputs,
  pkgs,
  lib,
  config,
  osConfig,
  darwinConfig,
  ...
}:
let
  cfg = config.corncheese.theming;
  themeDetails = lib.recursiveUpdate (import (../../common + "/themes/${cfg.theme}.nix") {
    inherit pkgs;
  }) cfg.themeOverrides;
  hasSystemStylix = osConfig != null || darwinConfig != null;
  useWalbridgePalette = pkgs.stdenv.hostPlatform.isLinux && config.corncheese.wm.enable;
  walbridgeVisualize =
    inputs.walbridge.packages.${pkgs.stdenv.hostPlatform.system}.walbridge-visualize;
in
{
  options = {
    corncheese.theming = {
      enable = lib.mkEnableOption "corncheese theming";
      theme = lib.mkOption {
        type = lib.types.str;
        description = "Theme to use";
      };
      themeOverrides = lib.mkOption {
        type = lib.types.anything;
        description = "Overrides for imported theme data";
        default = { };
      };
      themeDetails = lib.mkOption {
        type = lib.types.anything;
        description = "Imported theme data";
        readOnly = true;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    corncheese.theming.themeDetails = themeDetails;

    stylix =
      lib.optionalAttrs (!hasSystemStylix) {
        enable = true;
        polarity = "dark";
        image = themeDetails.wallpaper;
        paletteGenerator =
          lib.mkIf useWalbridgePalette
            inputs.walbridge.packages.${pkgs.stdenv.hostPlatform.system}.stylix-palette-generator;
        base16Scheme = lib.mkIf (
          !useWalbridgePalette
        ) "${pkgs.base16-schemes}/share/themes/${themeDetails.base16Scheme}.yaml";
        override = lib.mkIf (
          !useWalbridgePalette && themeDetails.stylixOverride != null
        ) themeDetails.stylixOverride;
        opacity = {
          terminal = themeDetails.opacity;
          applications = themeDetails.opacity;
          desktop = themeDetails.opacity;
          popups = themeDetails.opacity;
        };
        fonts.sizes.terminal = themeDetails.fontSize;
      }
      // {
        targets = {
          nvf.enable = false;
          vscode.profileNames = [ "default" ];
          firefox.profileNames = [ "default" ];
        };
      };

    home.packages = lib.optionals useWalbridgePalette [ walbridgeVisualize ];
  };
}
