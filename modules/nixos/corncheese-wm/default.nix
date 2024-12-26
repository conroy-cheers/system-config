{ lib, inputs, config, pkgs, ... }:

let
  cfg = config.corncheese.wm;
  inherit (lib) mkEnableOption mkIf;
in
{
  imports = [
    (import ./common/wayland.nix { inherit lib config pkgs; })
    (import ./common/fonts.nix { inherit lib config pkgs; })
  ];

  options = {
    corncheese.wm = {
      enable = mkEnableOption "corncheese system window manager setup";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      brightnessctl
    ];

    # hyprland Nix cache
    nix = {
      settings = {
        substituters = [
          "https://hyprland.cachix.org"
        ];
        trusted-public-keys = [
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        ];
      };
    };

    programs = {
      hyprland = {
        enable = true;
        xwayland.enable = true;
        package = inputs.hyprland.packages.${pkgs.system}.default;
        portalPackage = inputs.hyprland.packages.${pkgs.system}.xdg-desktop-portal-hyprland;
      };
    };

    #    programs.hyprland.package = let
    #      patch = ./displaylink-custom.patch;
    #    in
    #    inputs.hyprland.packages.${pkgs.system}.default.overrideAttrs (self: super: {
    #      postUnpack = ''
    #        rm $sourceRoot/subprojects/wlroots-hyprland/patches/nvidia-hardware-cursors.patch
    #        cp ${patch} $sourceRoot/subprojects/wlroots-hyprland/patches
    #      '';
    #    });

    xdg.portal = {
      enable = true;
      xdgOpenUsePortal = true;
      config = {
        common.default = [ "*" ];
        hyprland.default = [ "hyprland" ];
      };

      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
      ];
    };
  };
}
