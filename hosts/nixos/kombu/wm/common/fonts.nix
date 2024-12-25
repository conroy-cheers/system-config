{ config, pkgs, ... }:

let
  themeDetails = config.corncheese.theming.themeDetails;
in
{
  fonts.packages = with pkgs; [
    themeDetails.fontPkg
  ];
}
