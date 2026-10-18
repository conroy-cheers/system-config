{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.wm;
in
{
  config = lib.mkIf cfg.enable {
    fonts = {
      packages = with pkgs; [
        adwaita-fonts
        noto-fonts-cjk-sans
        noto-fonts-cjk-serif
      ];

      fontconfig.defaultFonts = {
        sansSerif = [
          "Noto Sans CJK SC"
          "DejaVu Sans"
        ];
        serif = [
          "Noto Serif CJK SC"
          "DejaVu Serif"
        ];
      };
    };
  };
}
