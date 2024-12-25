{ inputs, config, pkgs, ... }:

{
  imports = [
    (import ./common/wayland.nix)
    (import ./common/fonts.nix { inherit config pkgs; })
  ];

  environment.systemPackages = with pkgs; [
    brightnessctl
  ];


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
}
