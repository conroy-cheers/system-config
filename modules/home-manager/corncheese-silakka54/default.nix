{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.silakka54;
  silakka54 = lib.getExe pkgs.silakka54;
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "corncheese" "wm" "silakka54" "enable" ]
      [ "corncheese" "silakka54" "enable" ]
    )
  ];

  options.corncheese.silakka54 = {
    enable = lib.mkEnableOption "Silakka54 firmware and keymap synchronization";
    overlayLayers = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.listOf (
          lib.types.enum (
            map (layer: layer.name) (
              builtins.fromJSON (builtins.readFile ../../../packages/silakka54/configuration.json)
            ).via.layers
          )
        )
      );
      default = [
        "Num"
        "Nav"
        "Sym"
      ];
      example = [
        "Num"
        "Sym"
      ];
      description = ''
        Silakka54 layer names for which the keyboard layer viewer is shown.
        By default the overlay is shown for Num, Nav, and Sym, but not Base.
        Set this to null to show every layer. An empty list disables the
        overlay for Silakka54 without disabling synchronization.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [
          pkgs.silakka54
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          pkgs.keymap-editor
          pkgs.libnotify
        ];
      }

      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        systemd.user.services.silakka54-watch = {
          Unit = {
            Description = "Watch and reconcile Silakka54 VIA state";
            After = [ "default.target" ];
          };
          Service = {
            ExecStart = "${silakka54} watch";
            Restart = "on-failure";
            RestartSec = 2;
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
