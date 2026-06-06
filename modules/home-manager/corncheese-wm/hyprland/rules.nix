{ lib, config, ... }:

let
  cfg = config.corncheese.wm;
in
{
  wayland.windowManager.hyprland.settings = lib.mkIf cfg.enable {
    window_rule = [
      {
        match.class = "^(qalculate-gtk)$";
        float = true;
      }
      {
        match.class = "^(qalculate-gtk)$";
        opacity = 0.8;
      }
      {
        match.class = "^(thunar)$";
        float = true;
      }

      # Set content type "game" for games
      {
        match.class = "^(steam_app_[0-9]+)$";
        content = "game";
      }
      {
        match.class = "^(steam_app_[0-9]+)$";
        tag = "+game";
      }
      {
        match.class = "^gamescope$";
        content = "game";
      }
      {
        match.class = "^gamescope$";
        tag = "+game";
      }
      {
        match.class = "^Minecraft[*].*$";
        content = "game";
      }
      {
        match.class = "^Minecraft[*].*$";
        tag = "+game";
      }
      {
        match.content = 3;
        fullscreen = true;
      }

      # 1Password unlock dialog
      {
        match = {
          class = "^(1password)$";
          title = "^(1Password)$";
          float = true;
        };
        pin = true;
      }
      {
        match = {
          class = "^(1password)$";
          title = "^(1Password)$";
          float = true;
        };
        focus_on_activate = true;
      }

      {
        match = {
          class = "^(firefox)$";
          title = "^(Picture-in-Picture)$";
        };
        keep_aspect_ratio = true;
      }
      {
        match = {
          class = "^(firefox)$";
          title = "^(Picture-in-Picture)$";
        };
        border_size = 0;
      }
      {
        match = {
          class = "^(firefox)$";
          title = "^(Firefox)$";
        };
        pin = true;
      }
      {
        match = {
          class = "^(firefox)$";
          title = "^(Picture-in-Picture)$";
        };
        pin = true;
      }
      {
        match = {
          class = "^(firefox)$";
          title = "^(Firefox)$";
        };
        float = true;
      }
      {
        match = {
          class = "^(firefox)$";
          title = "^(Picture-in-Picture)$";
        };
        float = true;
      }

      {
        match.class = "^(com.mitchellh.ghostty)$";
        opacity = 1.0;
      }
      {
        match.class = "^(com.mitchellh.ghostty)$";
        opaque = false;
      }
      {
        match.class = "^(org.wezfurlong.wezterm)$";
        opacity = 1.0;
      }
      {
        match.class = "^(plexamp)$";
        workspace = "2 silent";
      }
      {
        match = {
          class = "^(com.mitchellh.ghostty)$";
          title = "^(ghostty-floating)$";
        };
        float = true;
      }
      {
        match = {
          class = "^(floating)$";
          title = "^(ghostty)$";
        };
        size = "50% 50%";
      }
      {
        match = {
          class = "^(floating)$";
          title = "^(ghostty)$";
        };
        center = true;
      }

      {
        match = {
          title = "^()$";
          class = "^(steam)$";
        };
        stay_focused = true;
      }
      {
        match = {
          title = "^()$";
          class = "^(steam)$";
        };
        min_size = "1 1";
      }

      {
        match.class = "^(moe.launcher.the-honkers-railway-launcher)$";
        float = true;
      }
      {
        match.class = "^(lutris)$";
        float = true;
      }
      {
        match.class = "^(lutris)$";
        size = "1880 990";
      }
      {
        match.class = "^(lutris)$";
        center = true;
      }
    ];

    workspace_rule = [
      {
        workspace = "special";
        gaps_in = 24;
        gaps_out = 64;
      }
    ];

  };
}
