# Material Symbols

Material Symbols Outlined font by Google, licensed under Apache 2.0 (see LICENSE).

Source: https://github.com/google/material-design-icons/tree/master/variablefont

The `material-symbols` Nix package supplies the font; the revision is pinned by
the flake's nixpkgs input. No SVG artwork or font binary is checked into this repo.
Slint embeds the glyphs used in `dashboard.slint` at their actual pixel sizes,
with additional 2× sizes for Retina previews. There is no runtime download.
