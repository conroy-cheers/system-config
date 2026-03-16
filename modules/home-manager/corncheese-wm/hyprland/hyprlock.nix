{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.wm;
in
{
  config = lib.mkIf cfg.enable {
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          after_sleep_cmd = "hyprctl dispatch dpms on";
          ignore_dbus_inhibit = false;
          lock_cmd = "hyprlock";
          before_sleep_cmd = "hyprlock";
        };

        listener = [
          {
            timeout = 900;
            on-timeout = "hyprlock";
          }
          {
            timeout = 7200;
            on-timeout = "hyprctl dispatch dpms off";
            on-resume = "hyprctl dispatch dpms on && kill -9 $(pgrep ags) && ags &!";
          }
        ];
      };
    };

    programs.hyprlock.enable = true;
    programs.hyprlock.settings = {
      general = {
        grace = 0;
        ignore_empty_input = true;
      };

      input-field = {
        monitor = "";
        size = "250, 50";
        outline_thickness = 0;
        dots_size = 0.26;
        # inner_color = "#${config.lib.stylix.colors.base05}";
        dots_spacing = 0.64;
        dots_center = true;
        fade_on_empty = true;
        placeholder_text = "<i>Password...</i>";
        hide_input = false;
        # check_color = "rgb(40, 200, 250)";
        position = "0, 50";
        halign = "center";
        valign = "bottom";
      };
    };
    programs.hyprlock.extraConfig = with config.lib.stylix.colors; ''
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

    services.hyprsunset.enable = true;
  };
}
