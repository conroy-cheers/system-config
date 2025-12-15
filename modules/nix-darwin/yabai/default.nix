{
  lib,
  pkgs,
  config,
  ...
}:

with lib;
let
  cfg = config.corncheese.yabai;
in
{
  imports = [ ];

  options = {
    corncheese.yabai = {
      enable = mkEnableOption "corncheese yabai config";
    };
  };

  config = mkIf cfg.enable (
    let
      setbg = pkgs.callPackage ./setbg { yabai = config.services.yabai.package; };
    in
    {
      environment.systemPackages = [
        setbg
      ];

      services = {
        yabai = {
          enable = true;
          package = pkgs.yabai;
          enableScriptingAddition = true;
          config = {
            layout = "bsp";
            focus_follows_mouse = "autoraise";
            mouse_follows_focus = "off";
            window_placement = "second_child";
            auto_balance = "off";
            split_ratio = 0.50;
            mouse_modifier = "cmd";
            mouse_action1 = "move";
            mouse_action2 = "resize";
            external_bar = "all:16:0";
            bottom_padding = 10;
            left_padding = 10;
            right_padding = 10;
            window_gap = 10;
            menubar_opacity = 0.0;
          };
        };

        jankyborders = {
          enable = true;
        };

        skhd = {
          enable = true;
          package = pkgs.skhd;
          skhdConfig = builtins.readFile ./skhdrc;
        };

        sketchybar = {
          enable = true;
          package = pkgs.efterklang-sketchybar;
        };
      };

      # For sketchybar
      fonts.packages = with pkgs; [
        sketchybar-app-font
        maple-nf
      ];

      system.activationScripts.postActivation.text = ''
        yabai --load-sa
      '';
    }
  );

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
