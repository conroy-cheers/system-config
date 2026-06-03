{
  fetchFromGitHub,
  fontconfig,
  gitMinimal,
  gtk3,
  keymap-drawer,
  librsvg,
  lib,
  pkg-config,
  python3,
  qmk,
  rustc,
  stdenv,
}:

let
  silakkaRev = "75d168c5eaea4bdb635313a8fbcdd6d7009b212f";
  vialQmkRev = "888e3804d89dfadc130c2ba7fe4693046fb6883d";
  python = python3.withPackages (ps: [ ps.pyyaml ]);
in
stdenv.mkDerivation {
  pname = "silakka54";
  version = "0-unstable-2026-05-20";

  src = fetchFromGitHub {
    owner = "Squalius-cephalus";
    repo = "silakka54";
    rev = silakkaRev;
    hash = "sha256-Fvt06QuQsRKP2O+DtSruXb08QFU8obY/Jz/gcaGc4+o=";
  };

  vialQmk = fetchFromGitHub {
    owner = "vial-kb";
    repo = "vial-qmk";
    rev = vialQmkRev;
    fetchSubmodules = true;
    hash = "sha256-0+3L7dppthZT/e59/8cL7Vl4zfrYCMslh4PAfB7SFEI=";
  };

  nativeBuildInputs = [
    gitMinimal
    keymap-drawer
    librsvg
    pkg-config
    python
    qmk
    rustc
  ];

  buildInputs = [
    gtk3
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    cp -r "$vialQmk" qmk
    chmod -R u+w qmk
    patchShebangs qmk/util qmk/lib/python
    cp -r "$src/firmware" qmk/keyboards/silakka54

    export XDG_CACHE_HOME="$TMPDIR/xdg-cache"
    export FONTCONFIG_FILE=${fontconfig.out}/etc/fonts/fonts.conf

    keymap_dir=qmk/keyboards/silakka54/keymaps/conroy
    mkdir -p "$keymap_dir"
    install -m 0644 ${./config.h} "$keymap_dir/config.h"
    install -m 0644 ${./rules.mk} "$keymap_dir/rules.mk"
    install -m 0644 qmk/keyboards/silakka54/keymaps/vial/vial.json "$keymap_dir/vial.json"

    mkdir -p generated layers
    python ${./generate-keymap.py} \
      --keymap ${./keymap.yaml} \
      --output-c "$keymap_dir/keymap.c" \
      --output-metadata generated/layer-metadata.json

    keymap draw -j ${./drawer-info.json} -o generated/silakka54-keymap.svg ${./keymap.yaml}
    for layer in Base Num Nav Sym; do
      layer_file=$(echo "$layer" | tr '[:upper:]' '[:lower:]')
      keymap draw -j ${./drawer-info.json} --select-layers "$layer" -o "layers/$layer_file.svg" ${./keymap.yaml}
      rsvg-convert -o "layers/$layer_file.png" "layers/$layer_file.svg"
    done

    substitute ${./layer-viewer.rs} generated/layer-viewer.rs \
      --replace-fail @asset_dir@ "$out/share/silakka54/keymap"

    rustc generated/layer-viewer.rs \
      -o silakka54-layer-viewer \
      $(pkg-config --libs-only-L gtk+-3.0) \
      $(pkg-config --libs-only-l gtk+-3.0)

    make -C qmk silakka54:conroy SKIP_GIT=yes

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm0644 qmk/silakka54_conroy.uf2 "$out/share/silakka54/firmware/silakka54-conroy.uf2"
    install -Dm0644 ${./keymap.yaml} "$out/share/silakka54/keymap/keymap.yaml"
    install -Dm0644 ${./drawer-info.json} "$out/share/silakka54/keymap/drawer-info.json"
    install -Dm0644 generated/layer-metadata.json "$out/share/silakka54/keymap/layer-metadata.json"
    install -Dm0644 generated/silakka54-keymap.svg "$out/share/silakka54/keymap/silakka54-keymap.svg"
    install -Dm0644 qmk/keyboards/silakka54/keymaps/conroy/keymap.c "$out/share/silakka54/keymap/keymap.c"
    install -Dm0644 ${./90-silakka54.rules} "$out/lib/udev/rules.d/90-silakka54.rules"

    for image in layers/*; do
      install -Dm0644 "$image" "$out/share/silakka54/keymap/$image"
    done

    install -Dm0755 silakka54-layer-viewer "$out/bin/silakka54-layer-viewer"

    runHook postInstall
  '';

  meta = {
    description = "Silakka54 Vial-QMK firmware, Gallium keymap images, and layer viewer";
    homepage = "https://github.com/Squalius-cephalus/silakka54";
    license = lib.licenses.gpl2Plus;
    mainProgram = "silakka54-layer-viewer";
    platforms = lib.platforms.linux;
  };
}
