{
  lib,
  stdenv,
  fetchFromGitHub,

  cmake,
  darwin,
}:
stdenv.mkDerivation rec {
  pname = "media-control";
  version = "0.7.2";

  src = fetchFromGitHub {
    owner = "ungive";
    repo = "media-control";
    tag = "v${version}";
    fetchSubmodules = true;
    hash = "sha256-GvdgkW3Jux5oEqj+UfgUyk/Xj8fcAWo9ZmaNDIR6vzY=";
  };

  postPatch = ''
    substituteInPlace mediaremote-adapter/CMakeLists.txt \
      --replace-fail "codesign --force --deep --sign -" "ls -l"
  '';

  nativeBuildInputs = [
    cmake
    darwin.sigtool
  ];

  meta = {
    platforms = lib.platforms.darwin;
  };
}
