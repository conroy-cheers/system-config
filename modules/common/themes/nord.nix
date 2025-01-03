{
  themeName = "nord";
  wallpaper = ../non-nix/wallpapers/green.jpg;
  override = null;

  # Override stylix theme of btop.
  btopTheme = "nord";

  # Hyprland and ags;
  opacity = 0.9;
  rounding = 15;
  shadow = true;
  bordersPlusPlus = false;
  ags = {
    theme = {
      palette = {
        widget = "#434c5e";
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
