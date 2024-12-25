{ inputs, config, lib, pkgs, ... }:

let
  cfg = config.corncheese.wm;
  themeDetails = config.corncheese.theming.themeDetails;
  inherit (lib) mkEnableOption mkIf;
in
{
  imports = [
    (import ./hyprland/ags.nix { inherit inputs pkgs lib config; })
    (import ./hyprland/env.nix { inherit pkgs lib config; })
    (import ./hyprland/binds.nix { inherit pkgs lib config; })
    (import ./hyprland/scripts.nix { inherit pkgs lib config; })
    (import ./hyprland/rules.nix { inherit pkgs lib config; })
    (import ./hyprland/settings.nix { inherit inputs pkgs lib config; })
    (import ./hyprland/plugins.nix { inherit pkgs lib config; })
    (import ./hyprland/hyprlock.nix { inherit pkgs lib config; })
  ];

  options =
    {
      corncheese.wm = {
        enable = mkEnableOption "corncheese window manager setup";
        ags.enable = mkEnableOption "ags widget system";
        hyprpaper.enable = mkEnableOption "hyprpaper wallpaper manager";
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
        ] ++ lib.optional themeDetails.bordersPlusPlus
          pkgs.hyprlandPlugins.borders-plus-plus;
      };

      services.hyprpaper = mkIf cfg.hyprpaper.enable {
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
