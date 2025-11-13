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
  wayland.windowManager.hyprland.settings = lib.mkIf cfg.enable {
    env = [
      "XDG_CURRENT_DESKTOP,Hyprland"
      "XDG_SESSION_TYPE,wayland"
      "XDG_SESSION_DEKSTOP,Hyprland"
      "QT_QPA_PLATFORM,wayland"
      "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
      "QT_AUTO_SCREEN_SCALE_FACTOR,1"
      "MOZ_ENABLE_WAYLAND,1"
      "ELECTRON_OZONE_PLATFORM_HINT,auto"
      "NIXOS_OZONE_WL,1"
    ]
    ++ (lib.optionals cfg.nvidia [
      "LIBVA_DRIVER_NAME,nvidia"
      "GBM_BACKEND,nvidia-drm"
      "__GLX_VENDOR_LIBRARY_NAME,nvidia"
      "WLR_NO_HARDWARE_CURSORS,1"
    ]);
  };
}
