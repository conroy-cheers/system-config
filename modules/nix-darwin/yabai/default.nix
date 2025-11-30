{
  lib,
  pkgs,
  config,
  ...
}:

with lib;
let
  cfg = config.corncheese.yabai;
in
{
  imports = [ ];

  options = {
    corncheese.yabai = {
      enable = mkEnableOption "corncheese yabai config";
    };
  };

  config = mkIf cfg.enable (
    let
      setbg = pkgs.callPackage ./setbg { yabai = config.services.yabai.package; };
    in
    {
      environment.systemPackages = [
        setbg
      ];

      services = {
        yabai = {
          enable = true;
          package = pkgs.yabai;
          enableScriptingAddition = true;
        };

        jankyborders = {
          enable = true;
        };

        skhd = {
          enable = true;
          package = pkgs.skhd;
          skhdConfig = builtins.readFile ./skhdrc;
        };

        sketchybar = {
          enable = true;
          package = pkgs.sketchybar;
          extraPackages = with pkgs; [
            jq
          ];
          # config = import (lib.getExe (pkgs.callPackage ./sketchybar { }));
        };
      };

      # TODO: make builtin module work with scripts
      # launchd.user.agents.sketchybar =
      #   let
      #     cfg = rec {
      #       package = pkgs.sketchybar;
      #       extraPackages = with pkgs; [ jq ];
      #       # configFile = lib.getExe (pkgs.callPackage ./sketchybar { sketchybar = package; });
      #     };
      #   in
      #   {
      #     path = [ cfg.package ] ++ cfg.extraPackages ++ [ config.environment.systemPath ];
      #     serviceConfig.ProgramArguments = [
      #       "${lib.getExe cfg.package}"
      #     ]
      #     ++ optionals (cfg.configFile != null) [
      #       "--config"
      #       "${cfg.configFile}"
      #     ];
      #     serviceConfig.KeepAlive = true;
      #     serviceConfig.RunAtLoad = true;
      #   };

      # For sketchybar
      # homebrew = {
      #   taps = [ "shaunsingh/SFMono-Nerd-Font-Ligaturized" ];
      #   casks = [ "font-sf-mono-nerd-font-ligaturized" ];
      # };
    }
  );

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
