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
    environment.systemPackages = [
      pkgs.wayland
      pkgs.wl-clipboard
    ];

    # # Configure xwayland
    # services.xserver = {
    #   enable = true;
    #   xkb = {
    #     variant = "";
    #     layout = "us";
    #     options = "grp:win_space_toggle";
    #   };
    #   # displayManager.startx = {
    #   #   enable = true;
    #   # };
    # };
  };
}
