{
  fetchFromGitHub,
  fontconfig,
  gitMinimal,
  gtk4,
  gtk4-layer-shell,
  hyprland,
  keymap-drawer,
  lib,
  pkg-config,
  python3,
  qmk,
  rustPlatform,
  rustc,
  stdenv,
  wrapGAppsHook4,
}:

let
  silakkaRev = "75d168c5eaea4bdb635313a8fbcdd6d7009b212f";
  vialQmkRev = "888e3804d89dfadc130c2ba7fe4693046fb6883d";
  python = python3.withPackages (ps: [ ps.pyyaml ]);
  layerViewer = rustPlatform.buildRustPackage {
    pname = "silakka54-layer-viewer";
    version = "0.1.0";

    src = lib.cleanSource ./layer-viewer;
    cargoLock.lockFile = ./layer-viewer/Cargo.lock;

    nativeBuildInputs = [
      pkg-config
    ];

    buildInputs = [
      gtk4
      gtk4-layer-shell
    ];

    dontWrapGApps = true;

    meta = {
      description = "GTK4 layer-shell HUD for Silakka54 layer and held-key reports";
      mainProgram = "silakka54-layer-viewer";
      platforms = lib.platforms.linux;
    };
  };
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
    pkg-config
    python
    qmk
    rustc
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    gtk4-layer-shell
  ];

  dontConfigure = true;

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : "${lib.makeBinPath [ hyprland ]}"
    )
  '';

  buildPhase = ''
    runHook preBuild

    cp -r "$vialQmk" qmk
    chmod -R u+w qmk
    patchShebangs qmk/util qmk/lib/python
    cp -r "$src/firmware" qmk/keyboards/silakka54

    export XDG_CACHE_HOME="$TMPDIR/xdg-cache"
    export FONTCONFIG_FILE=${fontconfig.out}/etc/fonts/fonts.conf
    keymap_hash=$(sha256sum ${./keymap.yaml} | awk '{print $1}')
    firmware_abi_hash=$(
      {
        printf '%s\n' \
          'silakka-rev:${silakkaRev}' \
          'vial-qmk-rev:${vialQmkRev}' \
          'sync-protocol:1'
        sha256sum \
          ${./config.h} \
          ${./rules.mk} \
          ${./generate-keymap.py} \
          qmk/keyboards/silakka54/keyboard.json \
          qmk/keyboards/silakka54/keymaps/vial/vial.json
      } | sha256sum | awk '{print $1}'
    )

    keymap_dir=qmk/keyboards/silakka54/keymaps/conroy
    mkdir -p "$keymap_dir"
    install -m 0644 ${./config.h} "$keymap_dir/config.h"
    install -m 0644 ${./rules.mk} "$keymap_dir/rules.mk"
    install -m 0644 qmk/keyboards/silakka54/keymaps/vial/vial.json "$keymap_dir/vial.json"

    mkdir -p generated layers
    python ${./generate-keymap.py} \
      --keymap ${./keymap.yaml} \
      --keyboard-json qmk/keyboards/silakka54/keyboard.json \
      --output-c "$keymap_dir/keymap.c" \
      --output-metadata generated/layer-metadata.json \
      --output-dynamic-keymap generated/dynamic-keymap.json \
      --output-dynamic-keymap-tsv generated/dynamic-keymap.tsv \
      --firmware-abi-hash "$firmware_abi_hash" \
      --keymap-hash "$keymap_hash"

    keymap draw -j ${./drawer-info.json} -o generated/silakka54-keymap.svg ${./keymap.yaml}

    substitute ${./sync.rs} generated/silakka54-sync.rs \
      --replace-fail @manifest_path@ "$out/share/silakka54/firmware/manifest.json" \
      --replace-fail @firmware_path@ "$out/share/silakka54/firmware/silakka54-conroy.uf2" \
      --replace-fail @dynamic_keymap_tsv@ "$out/share/silakka54/keymap/dynamic-keymap.tsv" \
      --replace-fail @firmware_abi_hash@ "$firmware_abi_hash" \
      --replace-fail @keymap_hash@ "$keymap_hash"

    rustc generated/silakka54-sync.rs -o silakka54-sync

    make -C qmk silakka54:conroy SKIP_GIT=yes

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm0644 qmk/silakka54_conroy.uf2 "$out/share/silakka54/firmware/silakka54-conroy.uf2"
    install -Dm0644 ${./keymap.yaml} "$out/share/silakka54/keymap/keymap.yaml"
    install -Dm0644 ${./drawer-info.json} "$out/share/silakka54/keymap/drawer-info.json"
    install -Dm0644 generated/layer-metadata.json "$out/share/silakka54/keymap/layer-metadata.json"
    install -Dm0644 generated/dynamic-keymap.json "$out/share/silakka54/keymap/dynamic-keymap.json"
    install -Dm0644 generated/dynamic-keymap.tsv "$out/share/silakka54/keymap/dynamic-keymap.tsv"
    install -Dm0644 generated/silakka54-keymap.svg "$out/share/silakka54/keymap/silakka54-keymap.svg"
    install -Dm0644 qmk/keyboards/silakka54/keymaps/conroy/keymap.c "$out/share/silakka54/keymap/keymap.c"
    install -Dm0644 ${./90-silakka54.rules} "$out/lib/udev/rules.d/90-silakka54.rules"
    cat > "$out/share/silakka54/firmware/manifest.json" <<EOF
    {
      "keyboard": "silakka54",
      "firmware_uf2": "$out/share/silakka54/firmware/silakka54-conroy.uf2",
      "usb": {
        "vid": "0xFEED",
        "pid": "0x1212"
      },
      "via": {
        "protocol_version": "0x0009",
        "dynamic_keymap_get_keycode": "0x04",
        "dynamic_keymap_set_keycode": "0x05",
        "bootloader_jump": "0x0B"
      },
      "silakka54_sync": {
        "query": "0x54",
        "bootloader_jump": "0x42",
        "version": 1
      },
      "firmware_abi_hash": "$firmware_abi_hash",
      "keymap_hash": "$keymap_hash",
      "dynamic_keymap": "$out/share/silakka54/keymap/dynamic-keymap.json"
    }
    EOF
    install -Dm0755 ${layerViewer}/bin/silakka54-layer-viewer "$out/bin/silakka54-layer-viewer"
    install -Dm0755 silakka54-sync "$out/bin/silakka54-sync"

    runHook postInstall
  '';

  meta = {
    description = "Silakka54 Vial-QMK firmware, Gallium keymap images, layer viewer, and sync tool";
    homepage = "https://github.com/Squalius-cephalus/silakka54";
    license = lib.licenses.gpl2Plus;
    mainProgram = "silakka54-sync";
    platforms = lib.platforms.linux;
  };
}
