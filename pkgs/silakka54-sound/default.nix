{
  faust,
  gcc,
  gtk2,
  lib,
  libjack2,
  pkg-config,
  stdenv,
  which,
}:

stdenv.mkDerivation {
  pname = "silakka54-sound";
  version = "1";
  src = ./.;

  nativeBuildInputs = [
    faust
    gcc
    pkg-config
    which
  ];
  buildInputs = [
    gtk2
    libjack2
  ];

  buildPhase = ''
    runHook preBuild
    faust -I ${faust}/share/faust -lang cpp -cn Silakka54DSP -vec -vs 32 silakka54-sound.dsp -o silakka54-dsp.cpp
    $CXX -std=c++17 -O3 -DNDEBUG -I${faust}/include $(pkg-config --cflags jack) \
      main.cpp -o silakka54-sound-engine $(pkg-config --libs jack) -pthread
    $CXX -std=c++17 -O2 -DNDEBUG $(pkg-config --cflags jack) \
      send.cpp -o silakka54-sound-send $(pkg-config --libs jack) -pthread
    $CXX -std=c++17 -O3 -DNDEBUG -I${faust}/include \
      selftest.cpp -o silakka54-sound-selftest -pthread

    cp ${faust}/share/faust/jack-gtk.cpp jack-gtk-no-connect.cpp
    substituteInPlace jack-gtk-no-connect.cpp \
      --replace-fail 'jackaudio audio;' 'jackaudio audio(false);'
    faust -I ${faust}/share/faust -a jack-gtk-no-connect.cpp -vec -vs 32 \
      silakka54-sound.dsp -o silakka54-sound-design.cpp
    $CXX -std=c++17 -O2 -DNDEBUG -I${faust}/include \
      -DPRESETDIR='"auto"' $(pkg-config --cflags jack gtk+-2.0) silakka54-sound-design.cpp \
      -o silakka54-sound-design $(pkg-config --libs jack gtk+-2.0) -pthread
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./silakka54-sound-selftest
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm0755 silakka54-sound-engine "$out/bin/silakka54-sound-engine"
    install -Dm0755 silakka54-sound-send "$out/bin/silakka54-sound-send"
    install -Dm0755 silakka54-sound-design "$out/bin/silakka54-sound-design"
    install -Dm0644 silakka54-sound.dsp "$out/share/silakka54-sound/silakka54-sound.dsp"
    runHook postInstall
  '';

  meta = {
    description = "Low-latency Faust synthesizer for Silakka54 semantic MIDI events";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "silakka54-sound-engine";
  };
}
