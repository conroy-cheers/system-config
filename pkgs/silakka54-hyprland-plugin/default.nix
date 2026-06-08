{
  hyprland,
  hyprlandPlugins,
  lib,
  meson,
  ninja,
}:

hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "silakka54-hyprland-plugin";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  inherit hyprland;

  nativeBuildInputs = [
    meson
    ninja
  ];

  meta = {
    description = "Hyprland geometry trigger for the Silakka54 layer viewer";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
