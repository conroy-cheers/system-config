{
  fetchFromGitHub,
  lib,
  stdenv,
  readline,
}:
stdenv.mkDerivation {
  pname = "sbarlua";
  version = "unstable-2026-03-06";

  src = fetchFromGitHub {
    owner = "FelixKratz";
    repo = "SbarLua";
    rev = "dba9cc421b868c918d5c23c408544a28aadf2f2f";
    hash = "sha256-lhLTrdufA3ALJ2S5HLdgNOr5seWIWEHkVhZNPObzbvI=";
  };

  postPatch = ''
    substituteInPlace makefile \
      --replace "clang" "$CC"
  '';

  buildInputs = [ readline ];

  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];

  installFlags = [ "INSTALL_DIR=$(out)/bin" ];

  meta = with lib; {
    description = "A Lua API for SketchyBar";
    homepage = "https://github.com/FelixKratz/SbarLua";
    license = licenses.gpl3Only;
    # require mach.h
    platforms = platforms.darwin;
  };
}
