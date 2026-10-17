{
  pkgs,
  enableXWayland ? true,
  transparent ? false,
  desktopProtocol ? null,
}:
let
  hyprland = (pkgs.hyprland.override { inherit enableXWayland; }).overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ pkgs.lib.optional transparent ./transparent-output.patch;
  });
  # Aquamarine 0.15.1 unconditionally requests newer compositor/seat/shell
  # versions than Weston and gamescope advertise. Negotiate the supported
  # version; this backend needs no requests beyond those versions.
  patchedAquamarine = pkgs.aquamarine.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./aquamarine-initial-configure.patch ];
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/backend/Wayland.cpp \
        --replace-fail '&wl_compositor_interface, 6)' '&wl_compositor_interface, std::min(version, 6u))' \
        --replace-fail '&wl_seat_interface, 9)' '&wl_seat_interface, std::min(version, 9u))' \
        --replace-fail '&xdg_wm_base_interface, 6)' '&xdg_wm_base_interface, std::min(version, 6u))'
    '';
  });
  aquamarine =
    if desktopProtocol == null then
      patchedAquamarine
    else
      patchedAquamarine.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./aquamarine-native.patch
          ./aquamarine-timing.patch
        ];
        postPatch = (old.postPatch or "") + ''
          cp ${desktopProtocol} protocols/steam-frame-desktop-v1.xml
        '';
      });
in
# The patches preserve the Aquamarine ABI.
# Scope it to this executable instead of rebuilding/replacing the host desktop.
pkgs.symlinkJoin {
  name = "hyprland-nested-${hyprland.version}";
  inherit (hyprland) version;
  meta = hyprland.meta // {
    outputsToInstall = [ "out" ];
  };
  paths = [ hyprland ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    rm "$out/bin/Hyprland"
    makeWrapper ${hyprland}/bin/Hyprland "$out/bin/Hyprland" \
      --set XDG_CURRENT_DESKTOP Hyprland \
      --set XDG_SESSION_TYPE wayland \
      --unset HYPRLAND_INSTANCE_SIGNATURE \
      --set HYPRLAND_NO_SD_VARS 1 \
      --set HYPRLAND_NO_SD_TARGET 1 \
      --set HYPRLAND_NO_SD_NOTIFY 1 \
      --prefix LD_LIBRARY_PATH : ${aquamarine}/lib
  '';
}
