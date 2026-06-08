{
  hyprland,
  hyprlandPlugins,
  lib,
  meson,
  ninja,
}:

hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "keyboard-layer-viewer-hyprland-plugin";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  inherit hyprland;

  nativeBuildInputs = [
    meson
    ninja
  ];

  meta = {
    description = "Hyprland geometry trigger for the keyboard layer viewer";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
