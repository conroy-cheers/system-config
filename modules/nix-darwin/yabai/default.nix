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

      system.activationScripts.extraActivation.text = lib.mkAfter ''
        ${lib.getExe config.services.yabai.package} --load-sa
      '';

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
            external_bar = "all:6:0";
            bottom_padding = 5;
            left_padding = 5;
            right_padding = 5;
            window_gap = 8;
            menubar_opacity = 0.0;
          };
          extraConfig = ''
            yabai -m signal --add event=dock_did_restart action="sudo yabai --load-sa"

            yabai -m rule --add app="^(LuLu|Vimac|Calculator|Software Update|Dictionary|VLC|System Preferences|System Settings|zoom.us|Photo Booth|Archive Utility|Python|LibreOffice|App Store|Steam|Alfred|Activity Monitor)$" manage=off
            yabai -m rule --add label="Finder" app="^Finder$" title="(Co(py|nnect)|Move|Info|Pref)" manage=off
            yabai -m rule --add label="Safari" app="^Safari$" title="^(General|(Tab|Password|Website|Extension)s|AutoFill|Se(arch|curity)|Privacy|Advance)$" manage=off
            yabai -m rule --add label="System Information" app="System Information" title="System Information" manage=off
          '';
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
    }
  );

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
