{ pkgs, ... }:
rec {
  theme = "catppuccin"; # Selected theme from themes directory (./themes/)
  themeDetails = import (./. + "/themes/${theme}.nix");

  font = "JetBrains Mono"; # Selected font
  fontPkg = (pkgs.nerdfonts.override { fonts = [ "JetBrainsMono" ]; });
  fontSize = 12; # Font size
}
