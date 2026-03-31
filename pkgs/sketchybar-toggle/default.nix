{
  fetchFromGitHub,
  lib,
  libiconv,
  replaceVars,
  sketchybar,
  swiftPackages,
}:
let
  sketchyBarController = replaceVars ./SketchyBarController.swift {
    sketchybarPath = lib.getExe sketchybar;
  };
in
swiftPackages.stdenv.mkDerivation (finalAttrs: {
  pname = "sketchybar-toggle";
  version = "unstable-b4a963e";

  src = fetchFromGitHub {
    owner = "malpern";
    repo = "sketchybar-toggle";
    rev = "b4a963e96d65156b32d92af3682d9a9b024a3b1d";
    hash = "sha256-4X958atBN4Tl75lrkR9a6YVNBnGXg6ToXhUJr1UTPjE=";
  };

  strictDeps = true;
  dontConfigure = true;

  postPatch = ''
    cp ${./EventTap.swift} Sources/SketchyBarToggleCore/EventTap.swift
    cp ${sketchyBarController} Sources/SketchyBarToggleCore/SketchyBarController.swift

    substituteInPlace Sources/SketchyBarToggleCore/PrerequisiteChecker.swift \
      --replace-fail 'if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/sketchybar") {' 'if true {' \
      --replace-fail 'sketchybarPath = "/opt/homebrew/bin/sketchybar"' 'sketchybarPath = "${lib.getExe sketchybar}"' \
      --replace-fail '} else if FileManager.default.fileExists(atPath: "/usr/local/bin/sketchybar") {' '} else if false {' \
      --replace-fail 'sketchybarPath = "/usr/local/bin/sketchybar"' 'sketchybarPath = "${lib.getExe sketchybar}"'

    substituteInPlace Sources/SketchyBarToggleCore/StateMachine.swift \
      --replace-fail 'timerQueue: DispatchQueue = .main' 'timerQueue: DispatchQueue = DispatchQueue.global(qos: .userInteractive)'

    substituteInPlace Sources/SketchyBarToggle/main.swift \
      --replace-fail 'app.run()' 'dispatchMain()'
  '';

  nativeBuildInputs = with swiftPackages; [
    swift
    swiftpm
  ];

  buildInputs = [
    libiconv
  ];

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    swift build -c release --product ${finalAttrs.pname} --skip-update
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    export HOME="$TMPDIR"
    install -Dm755 "$(swift build -c release --show-bin-path --skip-update)/${finalAttrs.pname}" "$out/bin/${finalAttrs.pname}"
    runHook postInstall
  '';

  meta = {
    description = "Lightweight macOS daemon that coordinates SketchyBar and the native menu bar";
    homepage = "https://github.com/malpern/sketchybar-toggle";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.conroy-cheers ];
    mainProgram = finalAttrs.pname;
    platforms = lib.platforms.darwin;
  };
})
