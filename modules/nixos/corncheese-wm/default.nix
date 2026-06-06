{
  lib,
  inputs,
  config,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.wm;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  hypr-pkgs = import inputs.hyprland.inputs.nixpkgs {
    system = pkgs.stdenv.hostPlatform.system;
  };

  hyprlandPackage =
    inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs
      (old: {
        env = (old.env or { }) // {
          NIX_CFLAGS_COMPILE =
            lib.optionalString (old.env ? NIX_CFLAGS_COMPILE) "${old.env.NIX_CFLAGS_COMPILE} "
            + "-fno-var-tracking-assignments";
        };
      });
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
        equalizer = {
          enable = mkEnableOption "AutoEQ headphone equalizer profile";
          defaultEnabled = mkOption {
            type = types.bool;
            default = true;
            description = lib.mdDoc ''
              Default runtime state for the MOTU M2 equalizer when no persisted
              user preference exists yet.
            '';
          };
        };
      };
      nvidia = mkEnableOption "special nvidia configuration";
      gaming.enable = mkEnableOption "corncheese gaming configuration";
    };
  };

  config = mkIf cfg.enable (
    lib.mkMerge [
      {
        warnings =
          lib.optional ((inputs.hyprland.rev or null) != "04435fb857d4e3c5845bc43b077568d28e048c54")
            "hyprland input changed; re-check whether the -fno-var-tracking-assignments GCC ICE workaround in modules/nixos/corncheese-wm/default.nix is still required.";

        environment.systemPackages = with pkgs; [
          brightnessctl
          seahorse
          file-roller
          gpu-screen-recorder-gtk
        ];

        hardware.graphics = {
          package = hypr-pkgs.mesa;
          package32 = hypr-pkgs.pkgsi686Linux.mesa;
        };

        fonts.fontconfig.enable = true;

        programs = {
          chromium.extraOpts = {
            AllowSystemNotifications = true;
            BrowserThemeColor = lib.mkForce config.lib.stylix.colors.withHashtag.base0D;
          };

          hyprland = {
            enable = true;
            xwayland.enable = true;
            withUWSM = true;
            package = hyprlandPackage;
            portalPackage =
              inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland.override
                {
                  hyprland = hyprlandPackage;
                };
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

          gpu-screen-recorder.enable = true;
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
                libxcursor
                libxi
                libxinerama
                libxscrnsaver
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
        programs.gamescope.enable = true;
        programs.gamemode.enable = true;
        environment.systemPackages = with pkgs; [
          (heroic.override {
            extraPkgs =
              pkgs': with pkgs'; [
                gamescope
                gamemode
              ];
          })
          steamtinkerlaunch
          prismlauncher
        ];
      })
    ]
  );
}
