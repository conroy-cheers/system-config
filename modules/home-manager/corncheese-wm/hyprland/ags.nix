{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
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
  # imports = [ inputs.ags.homeManagerModules.default ];

  # config = lib.mkIf (cfg.enable && cfg.ags.enable) {
  #   home.packages = with pkgs; [
  #     asztal
  #     bun
  #     fd
  #     dart-sass
  #     gtk3
  #     pulsemixer
  #     networkmanager
  #     pavucontrol
  #   ];

  #   programs.ags = {
  #     enable = true;
  #     configDir = ../ags;
  #   };

  #   home.file.".cache/ags/options-nix.json".text = (builtins.toJSON agsOptions);
  # };

  config = lib.mkIf (cfg.enable && cfg.ags.enable) {
    home.packages = with pkgs; [
      inputs.colorshell.packages.${system}.colorshell
    ];

    home.file.".cache/wal/colors.json".text = builtins.toJSON {
      special = {
        background = "#1e1e2e"; # base
        foreground = "#c2c1c5";
        cursor = "#c2c1c5";
      };
      colors = {
        base00 = "#1e1e2e"; # base
        base01 = "#181825"; # mantle
        base02 = "#313244"; # surface0
        base03 = "#45475a"; # surface1
        base04 = "#585b70"; # surface2
        base05 = "#cdd6f4"; # text
        base06 = "#f5e0dc"; # rosewater
        base07 = "#b4befe"; # lavender
        base08 = "#f38ba8"; # red
        base09 = "#fab387"; # peach
        base0A = "#f9e2af"; # yellow
        base0B = "#a6e3a1"; # green
        base0C = "#94e2d5"; # teal
        base0D = "#89b4fa"; # blue
        base0E = "#cba6f7"; # mauve
        base0F = "#f2cdcd"; # flamingo
      };
    };

    wayland.windowManager.hyprland.settings.exec-once = lib.mkBefore [
      "colorshell &"
    ];
  };
}
