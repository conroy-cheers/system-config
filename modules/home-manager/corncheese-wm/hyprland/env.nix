{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.wm;
  env = name: value: {
    _args = [
      name
      value
    ];
  };
in
{
  wayland.windowManager.hyprland.settings = lib.mkIf cfg.enable {
    env = [
      (env "XDG_CURRENT_DESKTOP" "Hyprland")
      (env "XDG_SESSION_TYPE" "wayland")
      (env "XDG_SESSION_DEKSTOP" "Hyprland")
      (env "QT_QPA_PLATFORM" "wayland")
      (env "QT_WAYLAND_DISABLE_WINDOWDECORATION" "1")
      (env "QT_AUTO_SCREEN_SCALE_FACTOR" "1")
      (env "MOZ_ENABLE_WAYLAND" "1")
      (env "ELECTRON_OZONE_PLATFORM_HINT" "auto")
      (env "NIXOS_OZONE_WL" "1")
    ]
    ++ (lib.optionals cfg.nvidia [
      (env "LIBVA_DRIVER_NAME" "nvidia")
      (env "GBM_BACKEND" "nvidia-drm")
      (env "__GLX_VENDOR_LIBRARY_NAME" "nvidia")
      (env "WLR_NO_HARDWARE_CURSORS" "1")
    ]);
  };
}
