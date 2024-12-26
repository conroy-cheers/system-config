{ lib, config, pkgs, inputs, ... }:
let
  cfg = config.corncheese.wm;
  themeDetails = config.corncheese.theming.themeDetails;
in
{
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      inputs.swww.packages.${pkgs.system}.swww
    ];

    wayland.windowManager.hyprland.settings = {
      monitor = [
        # "HDMI-A-1,3440x1440@144,0x0, 1"
        "DP-1,3440x1440@160,0x0,1"
        ",preferred,auto,1"
      ];

      exec-once = [
        "swww-daemon &"
        "ags &"
        # "hyprctl setcursor Catppuccin-Mocha-Lavender-Cursors 24"
        "[workspace 1 silent] kitty"
        "[workspace 2 silent] kitty btop"
        "[workspace 2 silent] kitty cava"
        "[workspace special silent] slack"
        "[workspace special silent] firefox"
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
        dim_special = 0.5;
        rounding = themeDetails.roundingRadius;
        blur = {
          enabled = true;
          special = true;
          brightness = 1.0;
          contrast = 1.0;
          noise = 0.02;
          passes = 2;
          size = 5;
        };

        drop_shadow = themeDetails.shadows;
        shadow_ignore_window = false;
        shadow_offset = "2 2";
        shadow_range = 20;
        # "col.shadow" = "rgba(${config.lib.stylix.colors.base00}ff)";
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
        };
      };

      device = {
        name = "logitech-usb-receiver-mouse";
        sensitivity = -1.0;
      };

      gestures = {
        workspace_swipe = true;
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
        always_center_master = true;
      };

      misc = {
        force_default_wallpaper = -1;
        vrr = 2;
      };
    };
  };
}
