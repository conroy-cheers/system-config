{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.corncheese.wm.audio;
in
{
  config = lib.mkIf cfg.enable {
    security.rtkit.enable = true;
    services.pipewire = lib.mkMerge [
      ({
        enable = true;
        alsa = {
          enable = true;
          support32Bit = true;
        };
        pulse = {
          enable = true;
        };
        jack = {
          enable = true;
        };
      })
      (lib.mkIf cfg.equalizer.enable {
        extraConfig.pipewire."eq-ananda-stealth" = {
          "context.modules" = [
            {
              name = "libpipewire-module-parametric-equalizer";
              args = {
                "equalizer.filepath" = ./HIFIMAN-Ananda-Stealth-ParametricEq.txt;
                "equalizer.description" = "Ananda Stealth AutoEQ";
              };
            }
          ];
        };
      })
    ];
  };
}
