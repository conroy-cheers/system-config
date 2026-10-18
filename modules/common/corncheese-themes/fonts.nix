{ pkgs }:
{
  # Shared by themes and passed directly to stylix.fonts on every platform.
  # Override a theme's font with corncheese.theming.themeOverrides.fonts.monospace.
  monospace = {
    name = "MesloLGM Nerd Font Mono";
    package = pkgs.nerd-fonts.meslo-lg;
  };
  emoji = {
    name = "Noto Color Emoji";
    package = pkgs.noto-fonts-color-emoji;
  };
  sizes.terminal = 11;
}
