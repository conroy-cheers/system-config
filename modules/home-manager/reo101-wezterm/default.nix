{
  lib,
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
    programs.wezterm = {
      enable = true;
      extraConfig = builtins.concatStringsSep "\n" [
        (builtins.readFile ./wezterm.lua)
        cfg.extraConfig
      ];
    };
  };

  meta = {
  };
}
