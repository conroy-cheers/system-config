{
  inputs,
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
  useWalbridgePalette = pkgs.stdenv.hostPlatform.isLinux && config.corncheese.wm.enable;
in
{
  options = {
    corncheese.theming = {
      enable = lib.mkEnableOption "corncheese NixOS theming";
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

  imports = [ inputs.stylix.nixosModules.stylix ];

  config = lib.mkIf cfg.enable {
    corncheese.theming.themeDetails = themeDetails;

    fonts = {
      fontconfig.enable = true;
      packages = [ config.stylix.fonts.monospace.package ];
    };

    stylix = {
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
        terminal = cfg.themeDetails.opacity;
        applications = cfg.themeDetails.opacity;
        desktop = cfg.themeDetails.opacity;
        popups = cfg.themeDetails.opacity;
      };
      fonts.sizes.terminal = themeDetails.fontSize;
      cursor = lib.mkIf useWalbridgePalette {
        package = pkgs.catppuccin-cursors.mochaLavender;
        name = "catppuccin-mocha-lavender-cursors";
        size = 24;
      };

      targets.nvf.enable = false;
    };
  };
}
