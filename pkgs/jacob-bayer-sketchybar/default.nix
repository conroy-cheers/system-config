{
  lib,
  callPackage,
  stdenv,
  replaceVars,
  writeShellApplication,
  lua5_4,
  sbarlua,
  sketchybar,
  jq,
  switchaudio-osx,
  yabai,
}:
let
  sketchybarrc = replaceVars ./sketchybarrc {
    inherit sbarlua;
    lua = lua5_4;
  };
  initLua = ./init.lua;

  sketchybar-toggle = callPackage ../sketchybar-toggle { };

  sketchybar-config = stdenv.mkDerivation {
    pname = "jacob-bayer-sketchybar-config";
    version = "2026-03-28";

    src = ./.;

    postPatch = ''
      cp ${sketchybarrc} ./sketchybarrc
      cp ${initLua} ./init.lua
      chmod a+x ./sketchybarrc
    '';

    buildPhase = ''
      runHook preBuild
      cd helpers && make && cd ..
      runHook postBuild
    '';

    installPhase = ''
      cp -rp . "$out"
    '';
  };
in
writeShellApplication {
  name = "sketchybar";

  runtimeInputs = [
    jq
    sketchybar
    sketchybar-toggle
    switchaudio-osx
    yabai
  ];

  text = ''
    export CONFIG_DIR=${sketchybar-config}

    if [ "$#" -gt 0 ]; then
      exec ${lib.getExe sketchybar} "$@"
    fi

    exec ${lib.getExe sketchybar} --config ${sketchybar-config}/sketchybarrc
  '';

  derivationArgs = {
    passthru.config = sketchybar-config;
    passthru.sketchybarBinary = lib.getExe sketchybar;
  };
}
