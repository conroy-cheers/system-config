{
  inputs,
  pkgs,
  system,
  ...
}:

pkgs.keyboard-layer-viewer-hyprland-plugin.override {
  hyprland = inputs.hyprland.packages.${system}.default;
}
