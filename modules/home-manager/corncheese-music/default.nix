{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.corncheese.music;

  lv2Plugins = with pkgs; [
    neural-amp-modeler-lv2
  ];

  namModels = pkgs.fetchFromGitHub {
    owner = "pelennor2170";
    repo = "NAM_models";
    rev = "0e0bb0a853d4043de099ecac6f493c9501c1909b";
    hash = "sha256-KXHMHqwOev3yJCpKKIFwm/NMeRbPygVRcoh2CX6YMlU=";
  };
in
{
  imports = [ ];

  options = {
    corncheese.music = {
      enable = lib.mkEnableOption "corncheese music workstation";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      ardour
      lingot
    ];

    home.sessionVariables = {
      LV2_PATH = lib.concatMapStringsSep ":" (d: "${d}/lib/lv2") lv2Plugins;
    };

    home.file = {
      ".nam-models".source = namModels;
    };
  };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
