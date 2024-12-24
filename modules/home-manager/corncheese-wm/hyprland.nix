{ inputs, config, lib, pkgs, settings, ... }:

let
  cfg = config.corncheese.wm;

  inherit (lib)
    mkEnableOption mkOption types mkIf;
in
{
  imports = [
    mkIf cfg.ags (import ./hyprland/ags.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/env.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/binds.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/scripts.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/rules.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/settings.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/plugins.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/hyprlock.nix { inherit inputs pkgs settings lib config; })
  ];

  options =
    {
      corncheese.wm = {
        enable = mkEnableOption "corncheese window manager setup";
        ags = mkOption {
          description = "Enable ags";
          type = types.bool;
          default = true;
        };
        hyprpaper = mkOption {
          description = "Enable hyprpaper";
          type = types.bool;
          default = true;
        };
        bordersPlusPlus = mkOption {
          description = "Enable borders-plus-plus";
          type = types.bool;
          default = true;
        };
      };
    };

  config =
    mkIf cfg.enable {
      wayland.windowManager.hyprland = {
        enable = true;
        package = pkgs.hyprland;
        systemd.enable = true;
        plugins = [
          pkgs.hyprlandPlugins.hyprexpo
        ] ++ lib.optional (cfg.bordersPlusPlus)
          pkgs.hyprlandPlugins.borders-plus-plus;
      };

      services.hyprpaper = mkIf cfg.hyprpaper {
        enable = true;
      };

      # NOTE: this executable is used by greetd to start a wayland session when system boot up
      # with such a vendor-no-locking script, we can switch to another wayland compositor without modifying greetd's config in NixOS module
      home.file.".wayland-session" = {
        source = "${pkgs.hyprland}/bin/Hyprland";
        executable = true;
      };
    };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
