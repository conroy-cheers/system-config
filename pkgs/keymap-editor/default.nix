{
  gtk3,
  lib,
  pkg-config,
  rustc,
  stdenv,
}:

stdenv.mkDerivation {
  pname = "keymap-editor";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  nativeBuildInputs = [
    pkg-config
    rustc
  ];

  buildInputs = [
    gtk3
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    substitute main.rs generated-main.rs \
      --replace-fail @default_keymap@ "${../../packages/silakka54/keymap.yaml}"

    rustc --edition=2021 generated-main.rs \
      -o keymap-editor \
      $(pkg-config --libs-only-L gtk+-3.0) \
      $(pkg-config --libs-only-l gtk+-3.0)

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm0755 keymap-editor "$out/bin/keymap-editor"

    runHook postInstall
  '';

  meta = {
    description = "Interactive GTK keymap.yaml editor for Silakka54";
    license = lib.licenses.mit;
    mainProgram = "keymap-editor";
    platforms = lib.platforms.linux;
  };
}
