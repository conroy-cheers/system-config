{
  lib,
  stdenv,
}:

stdenv.mkDerivation {
  pname = "shrimpus-epaper-spi-test";
  version = "1";
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    $CC -std=c11 -D_DEFAULT_SOURCE -O2 -Wall -Wextra -Werror \
      ${./epaper-spi-test.c} -o shrimpus-epaper-spi-test
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 shrimpus-epaper-spi-test \
      $out/bin/shrimpus-epaper-spi-test
    runHook postInstall
  '';

  meta = {
    description = "Userspace SPI diagnostic for shrimpus's Waveshare e-paper panel";
    license = lib.licenses.mit;
    mainProgram = "shrimpus-epaper-spi-test";
    platforms = [ "aarch64-linux" ];
  };
}
