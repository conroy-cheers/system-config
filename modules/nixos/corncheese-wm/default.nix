{
  lib,
  inputs,
  config,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.wm;
  inherit (lib) mkEnableOption mkIf;

  hypr-pkgs = inputs.hyprland.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [
    (import ./audio { inherit lib config pkgs; })
    (import ./common/wayland.nix { inherit lib config pkgs; })
    (import ./common/fonts.nix { inherit lib config pkgs; })
  ];

  options = {
    corncheese.wm = {
      enable = mkEnableOption "corncheese system window manager setup";
      audio = {
        enable = mkEnableOption "audio configuration";
        equalizer.enable = mkEnableOption "AutoEQ headphone equalizer profile";
      };
      nvidia = mkEnableOption "special nvidia configuration";
      gaming.enable = mkEnableOption "corncheese gaming configuration";
    };
  };

  config = mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = with pkgs; [
          brightnessctl
          seahorse
          file-roller
        ];

        # hyprland Nix cache
        nix = {
          settings = {
            substituters = [ "https://hyprland.cachix.org" ];
            trusted-public-keys = [
              "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
            ];
          };
        };

        hardware.graphics = {
          package = hypr-pkgs.mesa;
          package32 = hypr-pkgs.pkgsi686Linux.mesa;
        };

        fonts.fontconfig.enable = true;

        programs = {
          hyprland = {
            enable = true;
            xwayland.enable = true;
            withUWSM = true;
            package = inputs.hyprland.packages.${pkgs.system}.default;
            portalPackage =
              inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
          };

          # thunar file manager
          thunar = {
            enable = true;
            plugins = with pkgs; [
              thunar-archive-plugin
              thunar-volman
            ];
          };

          _1password.enable = true;
          _1password-gui = {
            enable = true;
            polkitPolicyOwners = [ "conroy" ];
          };
        };

        services.gvfs.enable = true;
        services.tumbler.enable = true;

        # For home-manager xdg portal config
        environment.pathsToLink = [
          "/share/xdg-desktop-portal"
          "/share/applications"
        ];

        xdg.portal = {
          enable = true;
          xdgOpenUsePortal = true;
          config = {
            common.default = [ "gtk" ];
            hyprland.default = [ "hyprland" ];
          };
          extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        };

        services.gnome.gnome-keyring.enable = true;
        security.pam.services.greetd.enableGnomeKeyring = true;

        # https://github.com/systemd/systemd/issues/37590
        systemd.services = builtins.listToAttrs (
          map
            (service: {
              name = service;
              value.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS = "false";
            })
            [
              "systemd-suspend"
              "systemd-hibernate"
              "systemd-hybrid-sleep"
              "systemd-suspend-then-hibernate-sleep"
            ]
        );
      }
      (lib.mkIf cfg.gaming.enable {
        programs.steam = {
          enable = true;
          gamescopeSession.enable = true;
          package = pkgs.steam.override {
            extraPkgs =
              pkgs': with pkgs'; [
                xorg.libXcursor
                xorg.libXi
                xorg.libXinerama
                xorg.libXScrnSaver
                libpng
                libpulseaudio
                libvorbis
                stdenv.cc.cc.lib # Provides libstdc++.so.6
                libkrb5
                keyutils
                # Add other libraries as needed
              ];
          };
        };
        environment.systemPackages = with pkgs; [
          steamtinkerlaunch
          prismlauncher
        ];
      })
    ]
  );
}
