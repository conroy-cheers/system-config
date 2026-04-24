{
  lib,
  pkgs,
  config,
  ...
}:

with lib;
let
  cfg = config.corncheese.wezterm;
  themeDetails = config.corncheese.theming.themeDetails;
  terminalOpacity = themeDetails.terminalOpacity or themeDetails.opacity or 1.0;
  weztermConfig = builtins.replaceStrings
    [ "__WALBRIDGE_WINDOW_BACKGROUND_OPACITY__" ]
    [ (toString terminalOpacity) ]
    (builtins.readFile ./wezterm.lua);
in
{
  imports = [ ];

  options = {
    corncheese.wezterm = {
      enable = mkEnableOption "corncheese wezterm setup";
      extraConfig = mkOption {
        type = types.str;
        description = "Extra wezterm config";
        default = "";
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages =
      with pkgs;
      builtins.concatLists [
        [
          wezterm
          nerd-fonts.fira-code
        ]
      ];

    programs.wezterm = {
      enable = true;
      extraConfig = builtins.concatStringsSep "\n" [
        weztermConfig
        cfg.extraConfig
      ];
    };
  };

  meta = {
  };
}
