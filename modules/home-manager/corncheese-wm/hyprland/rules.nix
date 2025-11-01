{ lib, config, ... }:

let
  cfg = config.corncheese.wm;
in
{
  wayland.windowManager.hyprland.settings = lib.mkIf cfg.enable {
    layerrule = [
      "blur, waybar"
      "blur, swaync-control-center"
      "blur, gtk-layer-shell"
      "xray 1, gtk-layer-shell"
      "xray 1, waybar"
      "ignorezero, waybar"
      "ignorezero, gtk-layer-shell"
      "ignorealpha 0.5, swaync-control-center"
    ];

    windowrule = [
      "float,title:^(swayimg)(.*)$"
      "float,class:^(qalculate-gtk)$"
      "opacity 0.8,class:^(qalculate-gtk)$"
      "float,class:^(thunar)$"

      # Set content type "game" for games
      "content game,class:^(steam_app_[0-9]+)$"
      "tag +game,class:^(steam_app_[0-9]+)$"
      "workspace special,content:game"
      "fullscreen,content:game"

      # https://github.com/hyprwm/Hyprland/discussions/11978
      # "pin,class:^(1Password)$,title:^(1Password)$,floating:1"
      "fullscreen,class:^(1Password)$,title:^(1Password)$,floating:1"

      "keepaspectratio,class:^(firefox)$,title:^(Picture-in-Picture)$"
      "noborder,class:^(firefox)$,title:^(Picture-in-Picture)$"
      "pin,class:^(firefox)$,title:^(Firefox)$"
      "pin,class:^(firefox)$,title:^(Picture-in-Picture)$"
      "float,class:^(firefox)$,title:^(Firefox)$"
      "float,class:^(firefox)$,title:^(Picture-in-Picture)$"

      "float,class:^(com.mitchellh.ghostty)$,title:^(ghostty-floating)$"
      "size 50% 50%,class:^(floating)$,title:^(ghostty)$"
      "center,class:^(floating)$,title:^(ghostty)$"

      "stayfocused, title:^()$,class:^(steam)$"
      "minsize 1 1, title:^()$,class:^(steam)$"

      "float,class:^(moe.launcher.the-honkers-railway-launcher)$"
      "float,class:^(lutris)$"
      "size 1880 990,class:^(lutris)$"
      "center,class:^(lutris)$"

      # Chromium notification windows
      "float,title:^()$,class:^()$"
      "pin,title:^()$,class:^()$"
      "noborder,title:^()$,class:^()$"
      "opacity 0.95,title:^()$,class:^()$"
      "move 100%-w-15 40,title:^()$,class:^()$"
    ];

    workspace = [ "special,gapsin:24,gapsout:64" ];
  };
}
