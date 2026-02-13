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
      pkgs.uwsm
    ];

    home.file.".cache/wal/colors.json".text = builtins.toJSON {
      special = {
        background = "#1e1e2e"; # base
        foreground = "#c2c1c5";
        cursor = "#c2c1c5";
      };
      colors = {
        color0 = "#1e1e2e"; # base
        color1 = "#181825"; # mantle
        color2 = "#313244"; # surface0
        color3 = "#45475a"; # surface1
        color4 = "#585b70"; # surface2
        color5 = "#cdd6f4"; # text
        color6 = "#f5e0dc"; # rosewater
        color7 = "#b4befe"; # lavender
        color8 = "#f38ba8"; # red
        color9 = "#fab387"; # peach
        color10 = "#f9e2af"; # yellow
        color11 = "#a6e3a1"; # green
        color12 = "#94e2d5"; # teal
        color13 = "#89b4fa"; # blue
        color14 = "#cba6f7"; # mauve
        color15 = "#f2cdcd"; # flamingo
      };
    };

    systemd.user.services.colorshell = {
      Unit = {
        Description = "colorshell";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };

      Service = {
        ExecStart = "${
          inputs.colorshell.packages.${pkgs.stdenv.hostPlatform.system}.colorshell
        }/bin/colorshell";
        Restart = "on-failure";
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
