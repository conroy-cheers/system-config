{
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  autoPatchelfHook,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  lib,
  libgbm,
  libsecret,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxkbfile,
  libxrandr,
  makeDesktopItem,
  makeWrapper,
  nspr,
  nss,
  pango,
  requireFile,
  stdenv,
  systemd,
  wrapGAppsHook3,
}:

let
  pname = "stm32cubemx2";
  version = "1.1.1";

  desktopItem = makeDesktopItem {
    name = pname;
    desktopName = "STM32CubeMX2";
    genericName = "STM32 configuration tool";
    comment = "Configure STM32 microcontrollers and generate initialization code";
    exec = "stm32cubemx2 %F";
    icon = pname;
    categories = [ "Development" ];
    startupNotify = true;
  };

  libraries = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libgbm
    libsecret
    libxkbcommon
    nspr
    nss
    pango
    stdenv.cc.cc
    systemd
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbfile
    libxrandr
  ];
in
stdenv.mkDerivation {
  inherit pname version;

  src = requireFile {
    name = "stm32cubemx2-${version}-X64-Linux-installer";
    sha256 = "sha256-j8I9GWDKa6wJIuzTv6s014gfK+b7OC2AQwUD16AaDz0=";
    url = "https://www.st.com/en/development-tools/stm32cubemx2.html#get-software";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = libraries;

  # The installer is a Tauri front-end around a gzip-compressed tar payload.
  # Extracting that payload directly makes installation deterministic and avoids
  # running a graphical installer in the build sandbox.
  unpackPhase = ''
    runHook preUnpack

    set +o pipefail
    tail -c +12853518 "$src" | gzip -dc 2>/dev/null | tar -x
    set -o pipefail

    runHook postUnpack
  '';

  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    installRoot="$out/opt/stm32cubemx2"
    mkdir -p \
      "$installRoot" \
      "$out/bin" \
      "$out/share/applications" \
      "$out/share/icons/hicolor/256x256/apps"
    cp -a \
      .bin \
      LICENSES.txt \
      STM32CubeMX2.png \
      data \
      resources \
      stm32cubemx2 \
      "$installRoot"

    # Updates to the packaged application and tools belong in this derivation.
    # Packs and settings still use STM32CubeMX2's normal per-user directories.
    substituteInPlace \
      "$installRoot/resources/stm32cubemx-application/${version}/dist/resources/app/package.json" \
      --replace-fail \
      '"cube.cube-core.check-for-tool-updates-on-startup": true' \
      '"cube.cube-core.check-for-tool-updates-on-startup": false'
    substituteInPlace \
      "$installRoot/resources/stm32cubemx-application/${version}/dist/resources/app/lib/backend/main.js" \
      --replace-fail \
      'if(process.env.CI==="true"&&process.env.CI_TEST_BUNDLE_UPDATE_CHECK!=="true"){u.logger.info("Skipping bundle update check in CI environment");return}' \
      'if(!0){u.logger.info("Skipping bundle update check in immutable Nix package");return}'

    makeWrapper "$installRoot/stm32cubemx2" "$out/bin/stm32cubemx2" \
      --set ELECTRON_OZONE_PLATFORM_HINT wayland \
      --set NIXOS_OZONE_WL 1 \
      --prefix PATH : "$out/bin" \
      ''${gappsWrapperArgs[@]}
    makeWrapper "$installRoot/.bin/cube" "$out/bin/cube" \
      --set-default CUBE_BUNDLE_PATH "$installRoot/resources" \
      --set ELECTRON_OZONE_PLATFORM_HINT wayland \
      --set NIXOS_OZONE_WL 1 \
      --prefix PATH : "$out/bin"

    ln -s "$installRoot/STM32CubeMX2.png" \
      "$out/share/icons/hicolor/256x256/apps/stm32cubemx2.png"
    ln -s "${desktopItem}/share/applications/stm32cubemx2.desktop" \
      "$out/share/applications"

    runHook postInstall
  '';

  meta = {
    description = "STM32 configuration and code-generation environment";
    homepage = "https://www.st.com/en/development-tools/stm32cubemx2.html";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.unfree;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
  };
}
