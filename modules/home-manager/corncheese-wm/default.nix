{ inputs, config, lib, pkgs, ... }:

let
  cfg = config.corncheese.wm;
  themeDetails = config.corncheese.theming.themeDetails;
  inherit (lib) mkEnableOption mkOption mkIf;
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
        environment = mkOption {
          type = with lib.types; attrsOf str;
          default = {};
          example = {
            XCURSOR_SIZE = "24";
            WLR_NO_HARDWARE_CURSORS = "1";
            NIXOS_OZONE_WL = "1";
          };
          description = lib.mdDoc ''
            Environment variables to be set when launching Hyprland.
            These variables will be exported in the wrapper script before executing Hyprland.

            Each attribute in this set represents an environment variable, where the attribute name
            is the variable name and its value is the variable's value.
          '';
        };
        ags.enable = mkEnableOption "ags widget system";
        hyprpaper.enable = mkEnableOption "hyprpaper wallpaper manager";
        firefox.enable = mkEnableOption "firefox configuration";
      };
    };

  config =
    mkIf cfg.enable {
      wayland.windowManager.hyprland = {
        enable = true;
        package = pkgs.hyprland;
        systemd.enable = true;
        plugins = [
          # pkgs.hyprlandPlugins.hyprexpo
        ] ++ lib.optional themeDetails.bordersPlusPlus
          pkgs.hyprlandPlugins.borders-plus-plus;
      };

      services.hyprpaper = mkIf cfg.hyprpaper.enable {
        enable = true;
      };

      # Stylix tries to set hyprlock wallpaper. We don't want this
      stylix.targets.hyprlock.enable = false;

      # NOTE: this executable is used by greetd to start a wayland session when system boot up
      # with such a vendor-no-locking script, we can switch to another wayland compositor without modifying greetd's config in NixOS module
      home.file.".wayland-session" = {
        text = ''
          #!${pkgs.bash}/bin/bash
          ${builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (name: value: 
            "export ${name}=\"${value}\"") cfg.environment))}
          exec ${pkgs.hyprland}/bin/Hyprland
        '';
	      executable = true;
      };

      programs.firefox = mkIf cfg.firefox.enable {
        profiles.conroy = {
          id = 0;
          isDefault = true;
          extensions = with pkgs.nur.repos.rycee.firefox-addons; [
            onepassword-password-manager
            ublock-origin
          ];
        };
      };

      programs.kitty.extraConfig = ''
        touch_scroll_multiplier 8.0
      '';
    };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
