{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.wm;
  themeDetails = config.corncheese.theming.themeDetails;
  inherit (lib) mkEnableOption mkOption mkIf;
in
{
  imports = [
    (import ./hyprland/ags.nix {
      inherit
        inputs
        pkgs
        lib
        config
        ;
    })
    (import ./hyprland/env.nix { inherit pkgs lib config; })
    (import ./hyprland/binds.nix { inherit pkgs lib config; })
    (import ./hyprland/scripts.nix { inherit pkgs lib config; })
    (import ./hyprland/rules.nix { inherit pkgs lib config; })
    (import ./hyprland/settings.nix {
      inherit
        inputs
        pkgs
        lib
        config
        ;
    })
    (import ./hyprland/plugins.nix { inherit pkgs lib config; })
    (import ./hyprland/hyprlock.nix { inherit pkgs lib config; })
  ];

  options = {
    corncheese.wm = {
      enable = mkEnableOption "corncheese window manager setup";
      environment = mkOption {
        type = with lib.types; attrsOf str;
        default = { };
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
      nvidia = mkEnableOption "special nvidia environment options";
      ags.enable = mkEnableOption "ags widget system";
      hyprpaper.enable = mkEnableOption "hyprpaper wallpaper manager";
      enableFancyEffects = mkEnableOption "GPU-intensive effects";
    };
  };

  config = mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      package = pkgs.hyprland;
      systemd.enable = true;
      plugins = [
        # pkgs.hyprlandPlugins.hyprexpo
      ]
      ++ lib.optional themeDetails.bordersPlusPlus pkgs.hyprlandPlugins.borders-plus-plus;
    };

    services.hyprpaper = mkIf cfg.hyprpaper.enable { enable = true; };

    # Stylix tries to set hyprlock wallpaper. We don't want this
    stylix.targets.hyprlock.enable = false;

    gtk = {
      enable = true;
      iconTheme = {
        package = pkgs.papirus-icon-theme;
        name = "Papirus";
      };
    };

    # NOTE: this executable is used by greetd to start a wayland session when system boot up
    # with such a vendor-no-locking script, we can switch to another wayland compositor without modifying greetd's config in NixOS module
    home.file.".wayland-session" = {
      text = ''
        #!${pkgs.bash}/bin/bash
        ${builtins.concatStringsSep "\n" (
          builtins.attrValues (builtins.mapAttrs (name: value: ''export ${name}="${value}"'') cfg.environment)
        )}
        exec ${pkgs.hyprland}/bin/Hyprland
      '';
      executable = true;
    };

    home.pointerCursor = {
      enable = true;
      package = pkgs.catppuccin-cursors.mochaLavender;
      name = "catppuccin-mocha-lavender-cursors";
      size = 24;
      gtk.enable = true;
      hyprcursor = {
        enable = true;
        # size = 24;
      };
    };

    xdg.portal = {
      enable = true;
      xdgOpenUsePortal = true;
      config = {
        common.default = [ "gtk" ];
        hyprland = {
          default = [ "hyprland" ];
          "org.freedesktop.impl.portal.Secret" = [
            "gnome-keyring"
          ];
        };
      };
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };

    xdg.userDirs = {
      enable = true;
      createDirectories = true;
      extraConfig = {
        XDG_SCREENSHOTS_DIR = "${config.home.homeDirectory}/Screenshots";
      };
    };

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "default-web-browser" = [ "chromium.desktop" ];
        "text/html" = [ "chromium.desktop" ];
        "x-scheme-handler/http" = [ "chromium.desktop" ];
        "x-scheme-handler/https" = [ "chromium.desktop" ];
        "x-scheme-handler/about" = [ "chromium.desktop" ];
        "x-scheme-handler/unknown" = [ "chromium.desktop" ];
        "inode/directory" = [ "thunar.desktop" ];
      };
    };

    systemd.user.services."1password" = {
      Unit = {
        Description = "1Password";
        Requires = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Install = {
        Alias = "1password.service";
        WantedBy = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs._1password-gui}/bin/1password --silent --ozone-platform wayland";
        Type = "exec";
        TimeoutSec = 60;
      };
    };
  };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
