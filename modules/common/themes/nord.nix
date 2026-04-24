{
  themeName = "nord";
  wallpaper = ../non-nix/wallpapers/green.jpg;
  override = null;
  terminalFontFamily = "MesloLGM Nerd Font Mono";
  terminalEmojiFontFamily = "Noto Color Emoji";

  # Override stylix theme of btop.
  btopTheme = "nord";

  # Hyprland and ags;
  opacity = 0.9;
  terminalBackgroundBlur = 0;
  terminalTuiTransparent = true;
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
