{ lib, pkgs, ... }:

let
  mkWallpaper = name: path:
    pkgs.runCommand "wallpaper-${name}" { } ''
      mkdir -p $out
      ln -s ${path} $out/wallpaper
    '';

  wallpapers = {
    green = mkWallpaper "green" ./images/green.jpg;
  };

  package = pkgs.runCommand "corncheese-wallpapers"
    {
      passthru = {
        inherit wallpapers;
        paths = lib.mapAttrs (name: wallpaper: "${wallpaper}/wallpaper") wallpapers;
      };

      meta = with lib; {
        description = "A curated collection of high-quality wallpapers";
        maintainers = with maintainers; [ conroy-cheers ];
        platforms = platforms.all;
      };
    } ''
    mkdir -p $out/share/wallpapers
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: path: ''
      ln -s ${path}/wallpaper $out/share/wallpapers/${name}
    '') wallpapers)}
  '';
in
package
