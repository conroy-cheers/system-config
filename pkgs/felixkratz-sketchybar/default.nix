{
  lib,
  callPackage,
  stdenv,
  fetchFromGitHub,
  replaceVars,
  writeShellApplication,

  lua5_4,
  sbarlua,
  sketchybar,
  jq,
  switchaudio-osx,
  imagemagick,
}:
let
  sketchybarrc = replaceVars ./sketchybarrc {
    inherit sbarlua;
    lua = lua5_4;
  };

  media-control = callPackage ../media-control { };
  sketchybar-system-stats = callPackage ../sketchybar-system-stats { };

  sketchybar-config = stdenv.mkDerivation {
    pname = "efterklang-sketchybar-config";
    version = "git";

    src = fetchFromGitHub {
      owner = "Efterklang";
      repo = "sketchybar";
      rev = "83be018aa4155f3c4de6cf033acf17112c1f8331";
      hash = "sha256-+A4Un1m1BJx5vX1IYxuPRgRH/9AWpUktcz1CaHTYDxI=";
    };

    postPatch = ''
      rm sketchybarrc
      cp ${sketchybarrc} ./sketchybarrc
      cp ${./settings.lua} ./settings.lua
      cp ${./init.lua} ./init.lua
      cp ${./icons.lua} ./icons.lua
      chmod a+x ./sketchybarrc

      # substituteInPlace items/front_app/front_app.lua \
      #   --replace-fail 'os.getenv("HOME")' '(os.getenv("HOME") or "~")'

      # substituteInPlace \
      #   # settings.lua \
      #   items/front_app/front_app.lua \
      #   --replace-fail '(os.getenv("HOME") or "~") .. "/.config/sketchybar' \"$out

      # substituteInPlace \
      #   helpers/sketchymenu/app_menu.sh \
      #   items/weather/ref/weather.sh \
      #   --replace-fail '$HOME/.config/sketchybar' $out

      # substituteInPlace \
      #   items/music/music.lua \
      #   --replace-fail '"􁁒"' "ICONS.media.menu"

      cat /dev/null > helpers/init.lua
    '';

    buildPhase = ''
      runHook preBuild

      cd helpers && make && cd ..

      runHook postBuild
    '';

    installPhase = ''
      cp -rp . $out
    '';
  };
in
writeShellApplication {
  name = "sketchybar";

  runtimeInputs = [
    sketchybar
    lua5_4
    jq
    switchaudio-osx
    media-control
    imagemagick
    sketchybar-system-stats
  ];

  text = ''
    ${lib.getExe sketchybar} --config ${sketchybar-config}/sketchybarrc
  '';

  derivationArgs = {
    passthru.config = sketchybar-config;
  };
}
