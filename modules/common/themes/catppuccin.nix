{ pkgs, ... }:

{
  base16Scheme = "catppuccin-mocha";
  # Stylix palette override.
  stylixOverride = {
    base00 = "11111b";
  };

  # Override stylix theme of btop.
  overrideBtop = true;
  btopTheme = "catppuccin";

  font = "Meslo LG";
  fontPkg = pkgs.nerd-fonts.meslo-lg;
  fontSize = 11;

  wallpaper = pkgs.corncheese-wallpapers.paths.green;

  # Hyprland and ags.
  opacity = 0.8; # affects theme.blur in ags.
  roundingRadius = 15; # affects theme.rounding in ags.
  shadows = false; # affects theme.shadows in ags.
  bordersPlusPlus = false;

  # Override default settings in ags.
  agsOverrides = {
    theme = {
      palette = {
        widget = "#25253a";
      };
      border = {
        width = 1;
        opacity = 96;
      };
    };
    bar = {
      curved = true;
    };
    widget = {
      opacity = 0;
    };
  };
}
