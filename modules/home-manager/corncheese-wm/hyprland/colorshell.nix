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
  walbridgePackage = inputs.walbridge.packages.${pkgs.stdenv.hostPlatform.system}.default;
  colorshellHyprlockTemplate = with config.lib.stylix.colors; ''
    source = ~/.cache/wal/colors-hyprland.conf

    background {
      monitor =
      color = rgb(${base00})
      path = $wallpaper
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
    home.packages = [
      walbridgePackage
      pkgs.libsForQt5.qt5ct
      pkgs.qt6Packages.qt6ct
    ];

    home.sessionVariables = {
      QT_QPA_PLATFORMTHEME = "qt5ct";
      QT_STYLE_OVERRIDE = "Fusion";
    };

    programs.colorshell = {
      settings = {
        wallpaper = {
          default_path = toString themeDetails.wallpaper;
        };
        theming = {
          apply_command = "${config.corncheese.theming.walbridgeApplyCommand} ${config.home.homeDirectory}/.cache/wal/colors.json";
        };
        idle = {
          lock_timeout = 900;
          lock_cmd = "colorshell lock";
          before_sleep_cmd = "colorshell lock";
          after_sleep_cmd = "hyprctl dispatch dpms on";
          ignore_dbus_inhibit = false;
          ignore_systemd_inhibit = false;
          ignore_wayland_inhibit = false;
          inhibit_sleep = 2;
          listeners = {
            display_power = {
              timeout = 7200;
              on_timeout = "hyprctl dispatch dpms off";
              on_resume = "hyprctl dispatch dpms on && systemctl --user restart colorshell.service";
            };
          };
        };
      };
      hyprlock.text = colorshellHyprlockTemplate;
    };
  };
}
