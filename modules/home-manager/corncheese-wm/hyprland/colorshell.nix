{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.corncheese.wm;
  colorshellEnabled = lib.attrByPath [ "programs" "colorshell" "enable" ] false config;
  themeDetails = config.corncheese.theming.themeDetails;
  colorshellPackage = inputs.colorshell.packages.${pkgs.stdenv.hostPlatform.system}.colorshell;
  colorshellHyprlockTemplate = with config.lib.stylix.colors; ''
    background {
      monitor =
      color = rgb(${base00})
      path = ${themeDetails.wallpaper}
    }

    general {
      grace = 0
      ignore_empty_input = true
    }

    input-field {
      monitor =
      size = 250, 50
      outline_thickness = 0
      dots_size = 0.26
      dots_spacing = 0.64
      dots_center = true
      fade_on_empty = true
      placeholder_text = <i>Password...</i>
      hide_input = false
      check_color = rgb(${base0A})
      fail_color = rgb(${base08})
      font_color = rgb(${base05})
      inner_color = rgb(${base00})
      outer_color = rgb(${base03})
      position = 0, 50
      halign = center
      valign = bottom
    }

    label {
        monitor =
        text = cmd[update:1000] echo "<b><big> $(date +"%H:%M") </big></b>"
        color = rgba(${base00-rgb-r}, ${base00-rgb-g}, ${base00-rgb-b}, 0.7)

        font_size = 108
        font_family = MesloLGM Nerd Font Propo

        position = 0, 310
        halign = center
        valign = center

        shadow_passes = 4
        shadow_size = 4
        shadow_boost = 0.2
    }

    label {
        monitor =
        text = cmd[update:18000000] echo "<b> "$(date +'%A, %-d %B %Y')" </b>"
        color = rgba(${base00-rgb-r}, ${base00-rgb-g}, ${base00-rgb-b}, 0.7)

        font_size = 24
        font_family = MesloLGM Nerd Font Propo

        position = 0, 215
        halign = center
        valign = center

        shadow_passes = 4
        shadow_size = 4
        shadow_boost = 0.8
    }
  '';
in
{
  config = lib.mkIf (cfg.enable && colorshellEnabled) {
    stylix.targets = {
      hyprland.hyprpaper.enable = false;
      hyprpaper.enable = false;
      hyprlock.enable = false;
    };

    programs.colorshell = {
      package = colorshellPackage;
      settings = {
        color = {
          engine = "static";
          static = with config.lib.stylix.colors.withHashtag; {
            bg_primary = base00;
            bg_secondary = base01;
            bg_tertiary = base02;
            bg_translucent_primary = "oklch(from ${base00} l c h / .68)";
            bg_translucent_secondary = "oklch(from ${base01} l c h / .68)";
            bg_translucent_tertiary = "oklch(from ${base02} l c h / .68)";
            fg_primary = base05;
            fg_disabled = base04;
          };
        };

        misc.match_window_border_color = false;
      };
    };

    programs.hyprlock.extraConfig = colorshellHyprlockTemplate;
  };
}
