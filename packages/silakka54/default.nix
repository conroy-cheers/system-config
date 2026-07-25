{
  fetchFromGitHub,
  fontconfig,
  gitMinimal,
  hidapi,
  keymap-drawer,
  lib,
  pkg-config,
  python3,
  qmk,
  rustPlatform,
  stdenv,
}:

let
  silakkaRev = "75d168c5eaea4bdb635313a8fbcdd6d7009b212f";
  vialQmkRev = "888e3804d89dfadc130c2ba7fe4693046fb6883d";
  compatibility = import ./firmware-compatibility.nix;
  keymapHash = builtins.hashFile "sha256" ./keymap.yaml;
  fingerprintMaterial = ''
    silakka54-firmware-fingerprint:1
    silakka-rev:${silakkaRev}
    vial-qmk-rev:${vialQmkRev}
    sync-protocol:1
    config.h:${builtins.hashFile "sha256" ./config.h}
    rules.mk:${builtins.hashFile "sha256" ./rules.mk}
    generate-keymap.py:${builtins.hashFile "sha256" ./generate-keymap.py}
    info.json:${builtins.hashFile "sha256" ./info.json}
    vial.json:${compatibility.vialJsonHash}
  '';
  sourceFingerprint = builtins.hashString "sha256" fingerprintMaterial;
  python = python3.withPackages (ps: [ ps.pyyaml ]);
  silakkaSource = fetchFromGitHub {
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
in
assert lib.assertMsg (sourceFingerprint == compatibility.sourceFingerprint) ''
  Silakka54 firmware inputs changed.
  Update packages/silakka54/firmware-compatibility.nix after deciding whether
  the existing compatibility ID is still valid. New fingerprint: ${sourceFingerprint}
'';
rustPlatform.buildRustPackage {
  pname = "silakka54";
  version = "0-unstable-2026-05-20";

  src = lib.cleanSource ./sync;
  cargoLock.lockFile = ./sync/Cargo.lock;

  nativeBuildInputs = [
    gitMinimal
    keymap-drawer
    pkg-config
    python
    qmk
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ hidapi ];

  preBuild = ''
    cp -r "${vialQmk}" qmk
    chmod -R u+w qmk
    patchShebangs qmk/util qmk/lib/python
    cp -r "${silakkaSource}/firmware" qmk/keyboards/silakka54
    install -m 0644 ${./info.json} qmk/keyboards/silakka54/keyboard.json

    actual_vial_json_hash=$(sha256sum qmk/keyboards/silakka54/keymaps/vial/vial.json | awk '{print $1}')
    if [[ "$actual_vial_json_hash" != "${compatibility.vialJsonHash}" ]]; then
      echo "Silakka54 Vial definition changed: $actual_vial_json_hash" >&2
      exit 1
    fi

    substituteInPlace qmk/lib/python/qmk/cli/generate/version_h.py \
      --replace-fail \
        'current_time = strftime(TIME_FMT)' \
        'current_time = "${compatibility.qmkBuildDate}"'

    export XDG_CACHE_HOME="$TMPDIR/xdg-cache"
    export FONTCONFIG_FILE=${fontconfig.out}/etc/fonts/fonts.conf

    keymap_dir=qmk/keyboards/silakka54/keymaps/conroy
    mkdir -p "$keymap_dir" generated
    install -m 0644 ${./config.h} "$keymap_dir/config.h"
    install -m 0644 ${./rules.mk} "$keymap_dir/rules.mk"
    install -m 0644 qmk/keyboards/silakka54/keymaps/vial/vial.json "$keymap_dir/vial.json"

    python ${./generate-keymap.py} \
      --keymap ${./keymap.yaml} \
      --info-json ${./info.json} \
      --output-c "$keymap_dir/keymap.c" \
      --output-metadata generated/layer-metadata.json \
      --output-dynamic-keymap generated/dynamic-keymap.json \
      --output-dynamic-keymap-tsv generated/dynamic-keymap.tsv \
      --firmware-abi-hash "${compatibility.id}" \
      --keymap-hash "${keymapHash}"

    keymap draw -j ${./info.json} -o generated/silakka54-keymap.svg ${./keymap.yaml}

    substituteInPlace src/main.rs \
      --replace-fail @manifest_path@ "$out/share/silakka54/firmware/manifest.json" \
      --replace-fail @firmware_path@ "$out/share/silakka54/firmware/silakka54-conroy.uf2" \
      --replace-fail @dynamic_keymap_tsv@ "$out/share/silakka54/keymap/dynamic-keymap.tsv" \
      --replace-fail @firmware_abi_hash@ "${compatibility.id}" \
      --replace-fail @keymap_hash@ "${keymapHash}"
  '';

  postBuild = ''
    mkdir -p qmk-userspace
    make -C qmk silakka54:conroy \
      SKIP_GIT=yes \
      QMK_USERSPACE="$PWD/qmk-userspace"
  '';

  postInstall = ''
    install -Dm0644 qmk/silakka54_conroy.uf2 "$out/share/silakka54/firmware/silakka54-conroy.uf2"
    install -Dm0644 ${./keymap.yaml} "$out/share/silakka54/keymap/keymap.yaml"
    install -Dm0644 ${./info.json} "$out/share/silakka54/keymap/info.json"
    install -Dm0644 generated/layer-metadata.json "$out/share/silakka54/keymap/layer-metadata.json"
    install -Dm0644 generated/dynamic-keymap.json "$out/share/silakka54/keymap/dynamic-keymap.json"
    install -Dm0644 generated/dynamic-keymap.tsv "$out/share/silakka54/keymap/dynamic-keymap.tsv"
    install -Dm0644 generated/silakka54-keymap.svg "$out/share/silakka54/keymap/silakka54-keymap.svg"
    install -Dm0644 qmk/keyboards/silakka54/keymaps/conroy/keymap.c "$out/share/silakka54/keymap/keymap.c"
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      install -Dm0644 ${./90-silakka54.rules} "$out/lib/udev/rules.d/90-silakka54.rules"
    ''}
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
      "firmware_abi_hash": "${compatibility.id}",
      "firmware_source_fingerprint": "${sourceFingerprint}",
      "keymap_hash": "${keymapHash}",
      "dynamic_keymap": "$out/share/silakka54/keymap/dynamic-keymap.json"
    }
    EOF
  '';

  passthru = {
    firmwareCompatibilityId = compatibility.id;
    firmwareSourceFingerprint = sourceFingerprint;
    inherit keymapHash;
  };

  meta = {
    description = "Silakka54 Vial-QMK firmware, Gallium keymap images, and cross-platform sync tool";
    homepage = "https://github.com/Squalius-cephalus/silakka54";
    license = lib.licenses.gpl2Plus;
    mainProgram = "silakka54-sync";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
