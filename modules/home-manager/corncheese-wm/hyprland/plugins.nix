{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.corncheese.wm;
  themeDetails = config.corncheese.theming.themeDetails;
in
{
  config = lib.mkIf cfg.enable {
    wayland.windowManager.hyprland.settings = lib.mkIf themeDetails.bordersPlusPlus {
      config.plugin."borders-plus-plus" = {
        add_borders = 2;
        border_size_1 = 3;
        border_size_2 = 10;
        natural_rounding = true;
      };
    };
  };
}
