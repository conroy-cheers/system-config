{
  lib,
  fetchurl,
  appimageTools,
  makeWrapper,
  plexamp,
}:

let
  upstreamPlexamp = plexamp;
  pname = "plexamp";
  version = "4.13.1";

  src = fetchurl {
    url = "https://plexamp.plex.tv/plexamp.plex.tv/desktop/Plexamp-${version}.AppImage";
    name = "${pname}-${version}.AppImage";
    hash = "sha512-HgF0+ojb0wOWO1DuiifiYMb0kSiRLvvMcteC89zZ4IYOflzOw+vNKoU+eyRo1Yl6irIL/Pg32eK4xRn5wyB46g==";
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };
in
assert lib.assertMsg (upstreamPlexamp.version == "4.13.0") ''
  The local plexamp overlay expects nixpkgs plexamp to still be 4.13.0.
  Upstream is now ${upstreamPlexamp.version}; remove or update the plexamp override in overlays/modifications/default.nix.
'';
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/plexamp.desktop $out/share/applications/plexamp.desktop
    install -m 444 -D ${appimageContents}/plexamp.svg \
      $out/share/icons/hicolor/scalable/apps/plexamp.svg
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace 'Exec=AppRun' 'Exec=${pname}'
    source "${makeWrapper}/nix-support/setup-hook"
    wrapProgram "$out/bin/plexamp" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
  '';

  meta = {
    description = "Beautiful Plex music player for audiophiles, curators, and hipsters";
    homepage = "https://plexamp.com/";
    changelog = "https://forums.plex.tv/t/plexamp-release-notes/221280/85";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [
      killercup
      redhawk
    ];
    platforms = [ "x86_64-linux" ];
  };
}
