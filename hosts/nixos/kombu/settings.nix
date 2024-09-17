{ pkgs, ... }:
rec {
  profile = "desktop"; # Select from profiles directory
  theme = "catppuccin"; # Selected theme from themes directory (./themes/)
  themeDetails = import (./. + "/themes/${theme}.nix");
  wm = [ "hyprland" "hyprland" ]; # Selected window manager or desktop environment;
  # must select one in both ./user/wm/ and ./system/wm/
  # Note, that first WM is incldued included into work profile
  # second one includes both.

  font = "JetBrains Mono"; # Selected font
  fontPkg = (pkgs.nerdfonts.override { fonts = [ "JetBrainsMono" ]; });
  fontSize = 12; # Font size

  icons = "Papirus";
  iconsPkg = pkgs.papirus-icon-theme;

  # Session variables.
  editor = "nvim"; # Default editor
  editorPkg = pkgs.neovim;
  browser = "firefox"; # Default browser; must select one from ./user/app/browser/
  browserPkg = pkgs.firefox;
  term = "kitty"; # Default terminal command
  termPkg = pkgs.kitty;
}
