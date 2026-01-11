{ lib, config, ... }:

let
  cfg = config.corncheese.wm;
in
{
  wayland.windowManager.hyprland.settings = lib.mkIf cfg.enable {
    layerrule = [
    ];

    windowrule = [
      "float yes,match:class ^(qalculate-gtk)$"
      "opacity 0.8,match:class ^(qalculate-gtk)$"
      "float yes,match:class ^(thunar)$"

      # Set content type "game" for games
      "content game,match:class ^(steam_app_[0-9]+)$"
      "tag +game,match:class ^(steam_app_[0-9]+)$"
      "content game,match:class ^gamescope$"
      "tag +game,match:class ^gamescope$"
      "fullscreen yes,match:content 3" # fullscreen all games

      # 1Password unlock dialog
      "pin yes,match:class ^(1password)$,match:title ^(1Password)$,match:float yes"

      "keep_aspect_ratio on,match:class ^(firefox)$,match:title ^(Picture-in-Picture)$"
      "border_size 0,match:class ^(firefox)$,match:title ^(Picture-in-Picture)$"
      "pin yes,match:class ^(firefox)$,match:title ^(Firefox)$"
      "pin yes,match:class ^(firefox)$,match:title ^(Picture-in-Picture)$"
      "float yes,match:class ^(firefox)$,match:title ^(Firefox)$"
      "float yes,match:class ^(firefox)$,match:title ^(Picture-in-Picture)$"

      "float yes,match:class ^(com.mitchellh.ghostty)$,match:title ^(ghostty-floating)$"
      "size 50% 50%,match:class ^(floating)$,match:title ^(ghostty)$"
      "center yes,match:class ^(floating)$,match:title ^(ghostty)$"

      "stay_focused on, match:title ^()$,match:class ^(steam)$"
      "min_size 1 1, match:title ^()$,match:class ^(steam)$"

      "float yes,match:class ^(moe.launcher.the-honkers-railway-launcher)$"
      "float yes,match:class ^(lutris)$"
      "size 1880 990,match:class ^(lutris)$"
      "center yes,match:class ^(lutris)$"

      # Chromium notification windows
      "float yes,match:title ^()$,match:class ^()$"
      "pin yes,match:title ^()$,match:class ^()$"
      "border_size 0,match:title ^()$,match:class ^()$"
      "opacity 0.95,match:title ^()$,match:class ^()$"
      "move 100%-w-15 40,match:title ^()$,match:class ^()$"
    ];

    workspace = [ "special,gapsin:24,gapsout:64" ];
  };
}
