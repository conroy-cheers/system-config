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

    environment.sessionVariables = {
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
      NIXOS_OZONE_WL = 1;
      __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json";
    };

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
