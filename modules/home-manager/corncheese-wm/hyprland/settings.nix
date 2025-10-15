{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.corncheese.wm;
  themeDetails = config.corncheese.theming.themeDetails;
in
{
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      inputs.swww.packages.${pkgs.system}.swww
      cliphist
    ];

    wayland.windowManager.hyprland.settings = lib.mkMerge [
      {
        monitor = [ ",preferred,auto,1" ];

        exec-once = [
          "swww-daemon &"
          "ags &"
          "wl-paste --type text --watch cliphist store" # Stores only text data
          "wl-paste --type image --watch cliphist store" # Stores only image data
          "[workspace 1 silent] kitty"
          "[workspace 2 silent] kitty btop"
          "[workspace 2 silent] kitty cava"
          "[workspace 2 silent] plexamp"
          "[workspace special silent] slack --ozone-platform=wayland"
          "[workspace special silent] chromium --disable-features=WaylandWpColorManagerV1"
        ];

        general = {
          gaps_in = 8;
          gaps_out = 16;
          border_size = 2;
          allow_tearing = true;
          # "col.active_border" = "rgba(${config.lib.stylix.colors.base0D}ff)";
          # "col.inactive_border" = "rgba(${config.lib.stylix.colors.base02}ff)";
        };

        decoration = {
          dim_special = lib.mkDefault 0.5;
          rounding = themeDetails.roundingRadius;
          blur = {
            enabled = lib.mkDefault false;
          };
        };

        animations = {
          enabled = true;
          bezier = [
            "wind, 0.05, 0.9, 0.1, 1.0"
            "winIn, 0.1, 1.1, 0.1, 1.03"
            "winOut, 0.3, -0.3, 0, 1"
            "liner, 1, 1, 1, 1"
            "workIn, 0.72, -0.07, 0.41, 0.98"
          ];
          animation = [
            "windows, 1, 3, wind, slide"
            "windowsIn, 1, 3, winIn, slide"
            "windowsOut, 1, 2, winOut, slide"
            "windowsMove, 1, 3, wind, slide"
            "border, 1, 1, liner"
            "borderangle, 1, 30, liner, loop"
            "fade, 1, 8, default"
            "workspaces, 1, 2, wind"
            "specialWorkspace, 1, 2, workIn, slidevert"
          ];
        };

        debug = {
          disable_logs = false;
        };

        input = {
          kb_layout = "us";
          kb_options = "grp:win_space_toggle";
          follow_mouse = true;
          touchpad = {
            natural_scroll = true;
            scroll_factor = 0.3;
            clickfinger_behavior = true;
          };
        };

        device = {
          name = "logitech-pro-x-2-1";
          sensitivity = -0.5;
        };

        gestures = {
          workspace_swipe_distance = 200;
        };

        # dwindle = {
        #   # keep floating dimentions while tiling
        #   pseudotile = true;
        #   preserve_split = true;
        #   force_split = 2;
        #   split_width_multiplier = 1.5;
        # };

        master = {
          orientation = "center";
          mfact = 0.65;
        };

        ecosystem = {
          no_update_news = true;
          no_donation_nag = true;
        };

        misc = {
          force_default_wallpaper = 0;
          vrr = 2;
        };

        xwayland = {
          force_zero_scaling = true;
        };
      }
      (lib.mkIf cfg.enableFancyEffects {
        decoration = {
          dim_special = 0.2;
          shadow = lib.mkForce {
            enabled = true;
            range = 50;
            render_power = 2;
            color = "rgba(030a1420)";
            offset = "10 20";
            scale = 0.98;
          };
          blur = {
            enabled = true;
            size = 8;
            passes = 1;
            ignore_opacity = true;
            new_optimizations = true;
            xray = false;
            noise = 0.0117;
            contrast = 0.8916;
            brightness = 0.8172;
            vibrancy = 0.1696;
            vibrancy_darkness = 0.0;
            special = false;
            popups = true;
            popups_ignorealpha = 0.85;
          };
        };
      })
    ];
  };
}
