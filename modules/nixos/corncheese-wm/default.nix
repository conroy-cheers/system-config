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
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ brightnessctl ];

    # hyprland Nix cache
    nix = {
      settings = {
        substituters = [ "https://hyprland.cachix.org" ];
        trusted-public-keys = [
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        ];
      };
    };

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
        plugins = with pkgs.xfce; [
          thunar-archive-plugin
          thunar-volman
        ];
      };
      file-roller.enable = true;

      _1password.enable = true;
      _1password-gui = {
        enable = true;
        polkitPolicyOwners = [ "conroy" ];
      };
    };

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

    # https://github.com/systemd/systemd/issues/37590
    systemd.services = builtins.listToAttrs (map (service: {
      name = service;
      value.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS = "false";
    }) [
      "systemd-suspend"
      "systemd-hibernate"
      "systemd-hybrid-sleep"
      "systemd-suspend-then-hibernate-sleep"
    ]);
  };
}
