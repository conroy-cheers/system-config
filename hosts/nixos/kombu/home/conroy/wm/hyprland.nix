{ inputs, config, lib, pkgs, ... }:

let
  settings = (import ../../../settings.nix { inherit pkgs; });
in
{
  imports = [
    (import ./hyprland/ags.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/env.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/binds.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/scripts.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/rules.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/settings.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/plugins.nix { inherit inputs pkgs settings lib config; })
    (import ./hyprland/hyprlock.nix { inherit inputs pkgs settings lib config; })
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    systemd.enable = true;
    plugins = [
      pkgs.hyprlandPlugins.hyprexpo
    ] ++ lib.optional (settings.themeDetails.bordersPlusPlus)
      pkgs.hyprlandPlugins.borders-plus-plus;
  };
}
