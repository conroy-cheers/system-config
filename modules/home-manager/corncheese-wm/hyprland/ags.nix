{ inputs, pkgs, lib, config, ... }:
let
  cfg = config.corncheese.wm;
  themeDetails = config.corncheese.theming.themeDetails;

  asztal = pkgs.callPackage ../ags/default.nix { inherit inputs; };
  agsColors = {
    wallpaper = themeDetails.wallpaper;
    theme = {
      blur = (1 - themeDetails.opacity) * 100;
      radius = themeDetails.roundingRadius;
      shadows = themeDetails.shadows;
      palette = {
        primary = {
          bg = "#${config.lib.stylix.colors.base0D}";
          fg = "#${config.lib.stylix.colors.base00}";
        };
        secondary = {
          bg = "#${config.lib.stylix.colors.base0E}";
          fg = "#${config.lib.stylix.colors.base00}";
        };
        error = {
          bg = "#${config.lib.stylix.colors.base06}";
          fg = "#${config.lib.stylix.colors.base00}";
        };
        bg = "#${config.lib.stylix.colors.base00}";
        fg = "#${config.lib.stylix.colors.base05}";
        widget = "#${config.lib.stylix.colors.base05}";
        border = "#${config.lib.stylix.colors.base05}";
      };
    };
    font = {
      size = themeDetails.fontSize;
      name = "${themeDetails.font}";
    };
    widget = {
      opacity = themeDetails.opacity * 100;
    };
  };
  agsOptions = lib.recursiveUpdate agsColors themeDetails.agsOverrides;
in
{
  imports = [ inputs.ags.homeManagerModules.default ];

  config = lib.mkIf cfg.ags.enable {
    home.packages = with pkgs; [
      asztal
      bun
      fd
      dart-sass
      gtk3
      pulsemixer
      networkmanager
      pavucontrol
    ];

    programs.ags = {
      enable = true;
      configDir = ../ags;
    };

    home.file.".cache/ags/options-nix.json".text = (builtins.toJSON agsOptions);
  };
}
