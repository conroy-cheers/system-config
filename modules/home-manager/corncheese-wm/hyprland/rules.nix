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
      "float,title:^(Qalculate!)$"
      "float,class:^(thunar)$"
    ];

    windowrulev2 = [
      "keepaspectratio,class:^(firefox)$,title:^(Picture-in-Picture)$"
      "noborder,class:^(firefox)$,title:^(Picture-in-Picture)$"
      "pin,class:^(firefox)$,title:^(Firefox)$"
      "pin,class:^(firefox)$,title:^(Picture-in-Picture)$"
      "float,class:^(firefox)$,title:^(Firefox)$"
      "float,class:^(firefox)$,title:^(Picture-in-Picture)$"

      "float,class:^(floating)$,title:^(kitty)$"
      "size 50% 50%,class:^(floating)$,title:^(kitty)$"
      "center,class:^(floating)$,title:^(kitty)$"

      "stayfocused, title:^()$,class:^(steam)$"
      "minsize 1 1, title:^()$,class:^(steam)$"

      "float,class:^(moe.launcher.the-honkers-railway-launcher)$"
      "float,class:^(lutris)$"
      "size 1880 990,class:^(lutris)$"
      "center,class:^(lutris)$"
    ];

    workspace = [ "special,gapsin:24,gapsout:64" ];
  };
}
