{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  cacert,
  libglvnd,
  libpulseaudio,
  libx11,
  libxkbcommon,
  wayland,
  xdg-utils,
  zlib,
  testers,
}:

let
  sources = {
    x86_64-linux = {
      filename = "rive-linux-x64.tar.gz";
      hash = "sha256-8cmercNZIPigqAK+voYHEB4YxYHAQKsNv5iJXP82hHc=";
    };
    aarch64-darwin = {
      filename = "rive-macos-arm64.tar.gz";
      hash = "sha256-Rx+dajdMlfkO6j7bm7i3eUwO1nh3FXRtK8P/GQAzKrM=";
    };
  };
  source = sources.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation (finalAttrs: {
  pname = "rive-cli";
  version = "1.5.1";

  # Upstream publishes the CLI as binaries; rive-runtime does not contain it.
  src = fetchurl {
    url = "https://releases.rive.app/cli/v${finalAttrs.version}/${source.filename}";
    inherit (source) hash;
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libglvnd
    libx11
    libxkbcommon
    wayland
    zlib
    stdenv.cc.cc.lib
  ];

  # The preview's audio backends are loaded with dlopen.
  runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux [
    (lib.getLib alsa-lib)
    (lib.getLib libpulseaudio)
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 rive "$out/libexec/rive-cli/rive"
    mkdir -p "$out/share/rive-cli"
    cp -r docs samples "$out/share/rive-cli/"

    makeWrapper "$out/libexec/rive-cli/rive" "$out/bin/rive" \
      --set-default SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
      --set-default RIVE_DOCS_DIR "$out/share/rive-cli/docs" \
      --set-default RIVE_SAMPLES_DIR "$out/share/rive-cli/samples" \
      ${lib.optionalString stdenv.hostPlatform.isLinux "--prefix PATH : ${lib.makeBinPath [ xdg-utils ]}"}

    runHook postInstall
  '';

  passthru.tests.version = testers.testVersion {
    package = finalAttrs.finalPackage;
  };

  meta = {
    description = "Create, preview, inspect, and publish Rive graphics from the command line";
    homepage = "https://rive.app/docs/cli/getting-started";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.unfree;
    mainProgram = "rive";
    platforms = builtins.attrNames sources;
  };
})
