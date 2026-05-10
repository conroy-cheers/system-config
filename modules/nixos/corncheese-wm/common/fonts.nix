{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.wm;
  themeDetails = config.corncheese.theming.themeDetails;
in
{
  config = lib.mkIf cfg.enable {
    fonts = {
      packages = with pkgs; [
        themeDetails.fontPkg
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
        monospace = [
          "Noto Sans Mono CJK SC"
          "DejaVu Sans Mono"
        ];
      };
    };
  };
}
