{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.silakka54;
  silakka54 = lib.getExe pkgs.silakka54;
  firmwarePrompt = pkgs.writeShellScript "silakka54-firmware-prompt" ''
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
  imports = [
    (lib.mkRenamedOptionModule
      [ "corncheese" "wm" "silakka54" "enable" ]
      [ "corncheese" "silakka54" "enable" ]
    )
  ];

  options.corncheese.silakka54.enable = lib.mkEnableOption "Silakka54 firmware and keymap synchronization";

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [ pkgs.silakka54 ];
      }

      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        systemd.user.services.silakka54-firmware-prompt = {
          Unit = {
            Description = "Prompt before flashing stale Silakka54 firmware";
            After = [ "graphical-session.target" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${firmwarePrompt}";
          };
        };

        systemd.user.services.silakka54-sync = {
          Unit = {
            Description = "Reconcile Silakka54 keymap after Home Manager activation";
            After = [ "default.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${silakka54} rebuild-switch";
          };
          Install.WantedBy = [ "default.target" ];
        };
      })

      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        launchd.agents.silakka54-sync = {
          enable = true;
          config = {
            ProgramArguments = [
              silakka54
              "watch"
            ];
            ProcessType = "Background";
            RunAtLoad = true;
            KeepAlive = true;
            ThrottleInterval = 5;
          };
        };
      })
    ]
  );
}
