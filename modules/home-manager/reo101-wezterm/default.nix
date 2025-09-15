{
  lib,
  pkgs,
  config,
  ...
}:

with lib;
let
  cfg = config.corncheese.wezterm;
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
        (builtins.readFile ./wezterm.lua)
        cfg.extraConfig
      ];
    };
  };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
