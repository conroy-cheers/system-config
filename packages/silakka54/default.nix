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
  qmkSource,
  qmkRev,
}:

let
  silakkaRev = "75d168c5eaea4bdb635313a8fbcdd6d7009b212f";
  configuration = builtins.fromJSON (builtins.readFile ./configuration.json);
  viaProtocolLine =
    lib.findFirst
      (
        line:
        builtins.match "[[:space:]]*#define VIA_PROTOCOL_VERSION 0x[0-9A-Fa-f]+[[:space:]]*" line != null
      )
      (throw "VIA_PROTOCOL_VERSION is absent from the pinned QMK input")
      (lib.splitString "\n" (builtins.readFile "${qmkSource}/quantum/via.h"));
  viaProtocolHex = builtins.head (
    builtins.match "[[:space:]]*#define VIA_PROTOCOL_VERSION 0x([0-9A-Fa-f]+)[[:space:]]*" viaProtocolLine
  );
  eepromGeneration = 2;
  defaultsHash = builtins.hashString "sha256" (builtins.toJSON configuration.via);
  abiHash = builtins.hashString "sha256" (
    builtins.toJSON {
      syncProtocol = 2;
      viaProtocol = viaProtocolHex;
      inherit eepromGeneration;
      matrix = {
        rows = 10;
        columns = 6;
      };
      layerCount = configuration.qmk.defines.DYNAMIC_KEYMAP_LAYER_COUNT;
      macroCount = configuration.qmk.defines.DYNAMIC_KEYMAP_MACRO_COUNT;
    }
  );
  runtimeMaterial = ''
    silakka54-runtime-fingerprint:3
    silakka-rev:${silakkaRev}
    qmk-rev:${qmkRev}
    eeprom-generation:${toString eepromGeneration}
    qmk-config:${builtins.toJSON configuration.qmk}
    qmk-system-control-descriptor.patch:${builtins.hashFile "sha256" ./qmk-system-control-descriptor.patch}
    generate-keymap.py:${builtins.hashFile "sha256" ./generate-keymap.py}
    info.json:${builtins.hashFile "sha256" ./info.json}
  '';
  runtimeHash = builtins.hashString "sha256" runtimeMaterial;
  python = python3.withPackages (ps: [ ps.hjson ]);
  silakkaSource = fetchFromGitHub {
    owner = "Squalius-cephalus";
    repo = "silakka54";
    rev = silakkaRev;
    hash = "sha256-Fvt06QuQsRKP2O+DtSruXb08QFU8obY/Jz/gcaGc4+o=";
  };
in
rustPlatform.buildRustPackage {
  pname = "silakka54";
  version = "0-unstable-2026-08-06";

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
    cp -r "${qmkSource}" qmk
    chmod -R u+w qmk
    patchShebangs qmk/util qmk/lib/python
    patch -d qmk -p1 < ${./qmk-system-control-descriptor.patch}
    cp -r "${silakkaSource}/firmware" qmk/keyboards/silakka54
    install -m 0644 ${./info.json} qmk/keyboards/silakka54/keyboard.json

    substituteInPlace qmk/lib/python/qmk/cli/generate/version_h.py \
      --replace-fail \
        'current_time = strftime(TIME_FMT)' \
        'current_time = "2026-08-06-00:00:0${toString eepromGeneration}"'

    export XDG_CACHE_HOME="$TMPDIR/xdg-cache"
    export FONTCONFIG_FILE=${fontconfig.out}/etc/fonts/fonts.conf

    keymap_dir=qmk/keyboards/silakka54/keymaps/system_config
    mkdir -p "$keymap_dir" generated

    python ${./extract-qmk-catalog.py} \
      --qmk qmk \
      --config ${./configuration.json} \
      --qmk-rev ${lib.escapeShellArg qmkRev} \
      --output generated/qmk-options.json

    python ${./generate-keymap.py} \
      --config ${./configuration.json} \
      --qmk-catalog generated/qmk-options.json \
      --info-json ${./info.json} \
      --output-c "$keymap_dir/keymap.c" \
      --output-config-h "$keymap_dir/config.h" \
      --output-rules-mk "$keymap_dir/rules.mk" \
      --output-keymap-yaml generated/keymap.yaml \
      --output-metadata generated/layer-metadata.json \
      --output-dynamic-keymap generated/dynamic-keymap.json \
      --output-dynamic-keymap-tsv generated/dynamic-keymap.tsv \
      --firmware-abi-hash "${abiHash}" \
      --runtime-hash "${runtimeHash}" \
      --defaults-hash "${defaultsHash}"

    keymap draw -j ${./info.json} -o generated/silakka54-keymap.svg generated/keymap.yaml

    substituteInPlace src/main.rs \
      --replace-fail @manifest_path@ "$out/share/silakka54/firmware/manifest.json" \
      --replace-fail @firmware_left_path@ "$out/share/silakka54/firmware/silakka54-conroy-left.uf2" \
      --replace-fail @firmware_right_path@ "$out/share/silakka54/firmware/silakka54-conroy-right.uf2" \
      --replace-fail @configuration_path@ "$out/share/silakka54/configuration.json" \
      --replace-fail @qmk_catalog_path@ "$out/share/silakka54/qmk-options.json" \
      --replace-fail @dynamic_keymap_tsv@ "$out/share/silakka54/keymap/dynamic-keymap.tsv" \
      --replace-fail @firmware_abi_hash@ "${abiHash}" \
      --replace-fail @runtime_hash@ "${runtimeHash}" \
      --replace-fail @keymap_hash@ "${defaultsHash}"
  '';

  postBuild = ''
    mkdir -p qmk-userspace
    make -C qmk silakka54:system_config \
      SKIP_GIT=yes \
      QMK_USERSPACE="$PWD/qmk-userspace" \
      EXTRAFLAGS=-DINIT_EE_HANDS_LEFT
    mv qmk/silakka54_system_config.uf2 generated/silakka54-conroy-left.uf2

    make -C qmk clean \
      SKIP_GIT=yes \
      QMK_USERSPACE="$PWD/qmk-userspace"
    make -C qmk silakka54:system_config \
      SKIP_GIT=yes \
      QMK_USERSPACE="$PWD/qmk-userspace" \
      EXTRAFLAGS=-DINIT_EE_HANDS_RIGHT
    mv qmk/silakka54_system_config.uf2 generated/silakka54-conroy-right.uf2
  '';

  postInstall = ''
    install -Dm0644 generated/silakka54-conroy-left.uf2 "$out/share/silakka54/firmware/silakka54-conroy-left.uf2"
    install -Dm0644 generated/silakka54-conroy-right.uf2 "$out/share/silakka54/firmware/silakka54-conroy-right.uf2"
    install -Dm0644 ${./configuration.json} "$out/share/silakka54/configuration.json"
    install -Dm0644 generated/qmk-options.json "$out/share/silakka54/qmk-options.json"
    install -Dm0644 generated/keymap.yaml "$out/share/silakka54/keymap/keymap.yaml"
    install -Dm0644 ${./info.json} "$out/share/silakka54/keymap/info.json"
    install -Dm0644 generated/layer-metadata.json "$out/share/silakka54/keymap/layer-metadata.json"
    install -Dm0644 generated/dynamic-keymap.json "$out/share/silakka54/keymap/dynamic-keymap.json"
    install -Dm0644 generated/dynamic-keymap.tsv "$out/share/silakka54/keymap/dynamic-keymap.tsv"
    install -Dm0644 generated/silakka54-keymap.svg "$out/share/silakka54/keymap/silakka54-keymap.svg"
    install -Dm0644 qmk/keyboards/silakka54/keymaps/system_config/keymap.c "$out/share/silakka54/keymap/keymap.c"
    install -Dm0644 qmk/keyboards/silakka54/keymaps/system_config/config.h "$out/share/silakka54/keymap/config.h"
    install -Dm0644 qmk/keyboards/silakka54/keymaps/system_config/rules.mk "$out/share/silakka54/keymap/rules.mk"
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      install -Dm0644 ${./90-silakka54.rules} "$out/lib/udev/rules.d/90-silakka54.rules"
    ''}
    cat > "$out/share/silakka54/firmware/manifest.json" <<EOF
    {
      "keyboard": "silakka54",
      "firmware_uf2": {
        "left": "$out/share/silakka54/firmware/silakka54-conroy-left.uf2",
        "right": "$out/share/silakka54/firmware/silakka54-conroy-right.uf2"
      },
      "usb": {
        "vid": "0xFEED",
        "pid": "0x1212"
      },
      "via": {
        "protocol_version": "0x${viaProtocolHex}",
        "dynamic_keymap_get_keycode": "0x04",
        "dynamic_keymap_set_keycode": "0x05",
        "bootloader_jump": "0x0B"
      },
      "silakka54_sync": {
        "query": "0x54",
        "bootloader_jump": "0x42",
        "version": 2
      },
      "qmk_revision": "${qmkRev}",
      "firmware_abi_hash": "${abiHash}",
      "runtime_hash": "${runtimeHash}",
      "factory_defaults_hash": "${defaultsHash}",
      "dynamic_keymap": "$out/share/silakka54/keymap/dynamic-keymap.json"
    }
    EOF
  '';

  passthru = {
    firmwareCompatibilityId = abiHash;
    firmwareSourceFingerprint = runtimeHash;
    keymapHash = defaultsHash;
    inherit qmkRev;
  };

  meta = {
    description = "Silakka54 upstream-QMK firmware, configuration, and cross-platform VIA sync tool";
    homepage = "https://github.com/Squalius-cephalus/silakka54";
    license = lib.licenses.gpl2Plus;
    mainProgram = "silakka54-sync";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
