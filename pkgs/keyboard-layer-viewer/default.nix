{
  gtk4,
  gtk4-layer-shell,
  hyprland,
  lib,
  pkg-config,
  rustPlatform,
  wrapGAppsHook4,
}:

rustPlatform.buildRustPackage {
  pname = "keyboard-layer-viewer";
  version = "0.1.0";

  src = lib.cleanSource ./source;
  cargoLock.lockFile = ./source/Cargo.lock;

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    gtk4-layer-shell
  ];

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : "${lib.makeBinPath [ hyprland ]}"
    )
  '';

  postInstall = ''
    install -Dm0644 ${./current-layer-hid.md} "$out/share/keyboard-layer-viewer/current-layer-hid.md"
  '';

  meta = {
    description = "GTK4 layer-shell HUD for keyboard current-layer reports";
    license = lib.licenses.mit;
    mainProgram = "keyboard-layer-viewer";
    platforms = lib.platforms.linux;
  };
}
