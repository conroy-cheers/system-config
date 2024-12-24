{
  themeName = "catppuccin-mocha";
  wallpaper = ../non-nix/wallpapers/green.jpg;
  # Stylix palette override.
  override = {
    base00 = "11111b";
  };

  # Override stylix theme of btop.
  overrideBtop = true;
  btopTheme = "catppuccin";

  # Hyprland and ags.
  opacity = 0.8; # affects theme.blur in ags.
  rounding = 15; # affects theme.rounding in ags.
  shadow = false; # affects theme.shadows in ags.
  bordersPlusPlus = false;

  # Override default settings in ags.
  ags = {
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
