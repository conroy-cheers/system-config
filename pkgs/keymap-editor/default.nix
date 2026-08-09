{
  callPackage,
  gtk3,
  inputs,
  lib,
  pkg-config,
  rustPlatform,
}:

let
  silakka54 = callPackage ../../packages/silakka54 {
    qmkSource = inputs.qmk;
    qmkRev = inputs.qmk.rev;
  };
in
rustPlatform.buildRustPackage {
  pname = "keymap-editor";
  version = "0.2.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    gtk3
  ];

  postPatch = ''
    substituteInPlace main.rs \
      --replace-fail @default_keymap@ "${../../packages/silakka54/configuration.json}" \
      --replace-fail @silakka54_sync@ "${lib.getExe silakka54}"
  '';

  preBuild = ''
    export RUSTFLAGS="$(pkg-config --libs-only-L gtk+-3.0) $(pkg-config --libs-only-l gtk+-3.0)"
  '';

  meta = {
    description = "Interactive GTK JSON configuration editor for Silakka54";
    license = lib.licenses.mit;
    mainProgram = "keymap-editor";
    platforms = lib.platforms.linux;
  };
}
