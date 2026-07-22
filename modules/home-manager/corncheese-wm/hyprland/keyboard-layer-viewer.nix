{
  config,
  lib,
  osConfig ? { },
  pkgs,
  ...
}:

let
  cfg = config.corncheese.wm;
  keyboardLayerViewerCfg = cfg.keyboardLayerViewer;
  luaString = builtins.toJSON;
  hyprlandPackage = osConfig.programs.hyprland.package or pkgs.hyprland;
  keyboardLayerViewer = lib.getExe pkgs.keyboard-layer-viewer;

  profileToJson = profile: {
    inherit (profile)
      id
      name
      vid
      pid
      info
      layers
      ;
    current_layer_hid = profile.currentLayerHid;
  };

  keyboardLayerViewerProfiles = pkgs.writeText "keyboard-layer-viewer-profiles.json" (
    builtins.toJSON {
      keyboards = map profileToJson (
        lib.optionals cfg.silakka54.enable [
          {
            id = "silakka54";
            name = "Silakka54";
            vid = "0xfeed";
            pid = "0x1212";
            info = "${pkgs.silakka54}/share/silakka54/keymap/info.json";
            layers = "${pkgs.silakka54}/share/silakka54/keymap/keymap.yaml";
            currentLayerHid = true;
          }
        ]
        ++ keyboardLayerViewerCfg.profiles
      );
    }
  );

  keyboardLayerViewerHyprlandPlugin = pkgs.keyboard-layer-viewer-hyprland-plugin.override {
    hyprland = hyprlandPackage;
  };

  keyboardLayerViewerControl = pkgs.writeShellScript "keyboard-layer-viewer-control" ''
    set -eu

    command="''${1:?usage: keyboard-layer-viewer-control <activity|hide|refresh-placement|place MONITOR LEFT_MARGIN>}"
    socket="''${XDG_RUNTIME_DIR:?}/keyboard-layer-viewer.sock"

    case "$command" in
      activity | hide | refresh-placement)
        ;;
      place)
        monitor="''${2:?usage: keyboard-layer-viewer-control place MONITOR LEFT_MARGIN}"
        left_margin="''${3:?usage: keyboard-layer-viewer-control place MONITOR LEFT_MARGIN}"
        ;;
      *)
        echo "unsupported keyboard-layer-viewer command: $command" >&2
        exit 64
        ;;
    esac

    if [ ! -S "$socket" ]; then
      exit 0
    fi

    case "$command" in
      activity)
        ${keyboardLayerViewer} --profiles ${keyboardLayerViewerProfiles} --refresh-placement || true
        exec ${keyboardLayerViewer} --profiles ${keyboardLayerViewerProfiles} --activity
        ;;
      place)
        exec ${keyboardLayerViewer} --profiles ${keyboardLayerViewerProfiles} --place "$monitor" "$left_margin"
        ;;
      refresh-placement)
        exec ${keyboardLayerViewer} --profiles ${keyboardLayerViewerProfiles} --refresh-placement
        ;;
      *)
        exec ${keyboardLayerViewer} --profiles ${keyboardLayerViewerProfiles} "--$command"
        ;;
    esac
  '';

  silakka54FirmwarePrompt = pkgs.writeShellScript "silakka54-firmware-prompt" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.silakka54
        pkgs.zenity
        pkgs.coreutils
        pkgs.systemd
      ]
    }:$PATH
    exec silakka54-sync prompt-firmware
  '';
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf keyboardLayerViewerCfg.enable {
        wayland.windowManager.hyprland = {
          plugins = lib.mkAfter [
            keyboardLayerViewerHyprlandPlugin
          ];
          settings.animation = lib.mkAfter [
            {
              leaf = "layers";
              enabled = true;
              speed = 3;
              bezier = "wind";
              style = "slide";
            }
            {
              leaf = "layersIn";
              enabled = true;
              speed = 3;
              bezier = "wind";
              style = "slide";
            }
            {
              leaf = "layersOut";
              enabled = true;
              speed = 2;
              bezier = "wind";
              style = "slide";
            }
          ];
          extraConfig = lib.mkAfter ''
            local keyboard_layer_viewer_control = ${luaString keyboardLayerViewerControl}

            hl.on("keybinds.submap", function(submap)
              if submap == "game" then
                hl.exec_cmd(keyboard_layer_viewer_control .. " hide")
              end
            end)

            hl.layer_rule({
              match = { namespace = "^keyboard-layer-viewer$" },
              blur = true,
              ignore_alpha = 0.4,
              animation = "slide",
            })
          '';
        };

        home.packages = [
          pkgs.keyboard-layer-viewer
        ];

        home.activation.loadKeyboardLayerViewerHyprlandPlugin = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
          runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          if [[ -d "$runtime_dir/hypr" ]]; then
            for instance in $(${hyprlandPackage}/bin/hyprctl instances -j | ${lib.getExe pkgs.jq} -r '.[].instance'); do
              if ! ${hyprlandPackage}/bin/hyprctl -i "$instance" plugin list | ${lib.getExe pkgs.gnugrep} -q 'Plugin keyboard-layer-viewer-hyprland-plugin'; then
                ${hyprlandPackage}/bin/hyprctl -i "$instance" plugin load ${keyboardLayerViewerHyprlandPlugin}/lib/libkeyboard-layer-viewer-hyprland-plugin.so >/dev/null || true
              fi
            done
          fi
        '';

        systemd.user.services.keyboard-layer-viewer = {
          Unit = {
            Description = "Keyboard layer viewer overlay";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = "${keyboardLayerViewer} --profiles ${keyboardLayerViewerProfiles} --hidden";
            ExecStopPost = "${lib.getExe' pkgs.coreutils "rm"} -f %t/keyboard-layer-viewer.sock";
            Restart = "on-failure";
            RestartSec = 1;
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      })

      (lib.mkIf cfg.silakka54.enable {
        home.packages = [ pkgs.silakka54 ];

        systemd.user.services.silakka54-firmware-prompt = {
          Unit = {
            Description = "Prompt before flashing stale Silakka54 firmware";
            After = [ "graphical-session.target" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${silakka54FirmwarePrompt}";
          };
        };

        systemd.user.services.silakka54-sync = {
          Unit = {
            Description = "Reconcile Silakka54 keymap after Home Manager activation";
            After = [ "default.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${lib.getExe pkgs.silakka54} rebuild-switch";
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
        };
      })
    ]
  );
}
