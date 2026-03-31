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
      sketchybarToggle = pkgs.callPackage ../../../pkgs/sketchybar-toggle { };
      applySketchybarPadding = pkgs.writeShellApplication {
        name = "apply-sketchybar-padding";

        runtimeInputs = with pkgs; [
          config.services.yabai.package
          jq
        ];

        text = ''
          set -euo pipefail

          native_json="$(
            /usr/bin/swift -e '
              import AppKit
              import CoreGraphics
              import Foundation

              func displayUUID(_ screen: NSScreen) -> String {
                let desc = screen.deviceDescription
                let id = (desc[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
                  return ""
                }
                return CFUUIDCreateString(nil, uuid) as String
              }

              let payload = NSScreen.screens.map { screen in
                let frame = screen.frame
                let visible = screen.visibleFrame
                let desc = screen.deviceDescription
                let id = (desc[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                return [
                  "uuid": displayUUID(screen),
                  "top": Int(frame.maxY - visible.maxY),
                  "builtin": CGDisplayIsBuiltin(id) != 0,
                ]
              }

              let data = try! JSONSerialization.data(withJSONObject: payload)
              print(String(data: data, encoding: .utf8)!)
            '
          )"

          assignments="$(
            yabai -m query --spaces |
              jq -r \
                --argjson native "$native_json" \
                --argjson displays "$(yabai -m query --displays)" \
                '
                  .[] as $space
                  | ($displays[] | select(.index == $space.display)) as $display
                  | (
                      ($native[] | select(.uuid == $display.uuid))
                      // {"top": 30, "builtin": false}
                    ) as $nativeDisplay
                  | (
                      if $nativeDisplay.builtin
                      then 0
                      else $nativeDisplay.top
                      end
                    ) as $top
                  | "\($space.index) \($top)"
                '
          )"

          while read -r space top; do
            [ -n "$space" ] || continue
            yabai -m config --space "$space" top_padding "$top"
          done <<EOF
          $assignments
          EOF
        '';
      };
    in
    {
      environment.systemPackages = [
        setbg
        applySketchybarPadding
        sketchybarToggle
      ];

      launchd.user.agents.sketchybar-toggle = {
        path = [ config.environment.systemPath ];

        serviceConfig = {
          ProgramArguments = [
            "${sketchybarToggle}/bin/sketchybar-toggle"
            "--trigger-zone"
            "20"
            "--menu-bar-height"
            "60"
            "--debounce"
            "120"
          ];
          KeepAlive = {
            SuccessfulExit = false;
          };
          RunAtLoad = true;
          LimitLoadToSessionType = "Aqua";
          StandardOutPath = "/tmp/sketchybar-toggle.log";
          StandardErrorPath = "/tmp/sketchybar-toggle.log";
          ThrottleInterval = 5;
          WorkingDirectory = "/tmp";
        };

        managedBy = "corncheese.yabai.enable";
      };

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
            external_bar = "off:0:0";
            top_padding = 0;
            bottom_padding = 5;
            left_padding = 5;
            right_padding = 5;
            window_gap = 8;
            # menubar_opacity = 0.0;
          };
          extraConfig = ''
            ${lib.getExe applySketchybarPadding}

            yabai -m signal --remove corncheese-dock-restart >/dev/null 2>&1 || true
            yabai -m signal --remove corncheese-space-created >/dev/null 2>&1 || true
            yabai -m signal --remove corncheese-space-destroyed >/dev/null 2>&1 || true
            yabai -m signal --remove corncheese-space-changed >/dev/null 2>&1 || true
            yabai -m signal --remove corncheese-display-added >/dev/null 2>&1 || true
            yabai -m signal --remove corncheese-display-removed >/dev/null 2>&1 || true
            yabai -m signal --remove corncheese-display-moved >/dev/null 2>&1 || true
            yabai -m signal --remove corncheese-display-changed >/dev/null 2>&1 || true

            yabai -m signal --add label=corncheese-dock-restart event=dock_did_restart action="sudo yabai --load-sa; ${lib.getExe applySketchybarPadding}"
            yabai -m signal --add label=corncheese-space-created event=space_created action="${lib.getExe applySketchybarPadding}"
            yabai -m signal --add label=corncheese-space-destroyed event=space_destroyed action="${lib.getExe applySketchybarPadding}"
            yabai -m signal --add label=corncheese-space-changed event=space_changed action="${lib.getExe applySketchybarPadding}"
            yabai -m signal --add label=corncheese-display-added event=display_added action="${lib.getExe applySketchybarPadding}"
            yabai -m signal --add label=corncheese-display-removed event=display_removed action="${lib.getExe applySketchybarPadding}"
            yabai -m signal --add label=corncheese-display-moved event=display_moved action="${lib.getExe applySketchybarPadding}"
            yabai -m signal --add label=corncheese-display-changed event=display_changed action="${lib.getExe applySketchybarPadding}"

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
          package = pkgs.jacob-bayer-sketchybar;
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
  };
}
