{
  fetchFromGitHub,
  ffmpeg-headless,
  lib,
  libcamera,
  libdatachannel,
  magic-enum,
  nlohmann_json,
  openssl,
  pkg-config,
  stdenv,
  v4l-utils,
  xxd,
}:

let
  version = "unstable-2026-03-02";
  rev = "e17a86e4f9bd0fda4bd901f14a5e2eef682962f8";
in
stdenv.mkDerivation {
  pname = "camera-streamer";
  inherit version;

  src = fetchFromGitHub {
    owner = "ayufan";
    repo = "camera-streamer";
    inherit rev;
    hash = "sha256-m79FSzWdX/xnbKaY9Qaon+zgmi4U/6A+OAUFruDjkxA=";
  };

  nativeBuildInputs = [
    pkg-config
    xxd
  ];

  buildInputs = [
    ffmpeg-headless
    libcamera
    libdatachannel
    magic-enum
    nlohmann_json
    openssl
    v4l-utils
  ];

  postPatch = ''
    mkdir -p third_party/magic_enum/include
    ln -s ${magic-enum}/include/magic_enum/magic_enum.hpp third_party/magic_enum/include/magic_enum.hpp

    substituteInPlace Makefile \
      --replace-fail 'CFLAGS := -Werror -Wall' 'CFLAGS := -Wall' \
      --replace-fail 'CFLAGS += -I$(LIBDATACHANNEL_PATH)/include' 'CFLAGS += -I${libdatachannel.dev}/include' \
      --replace-fail 'CFLAGS += -I$(LIBDATACHANNEL_PATH)/deps/json/include' 'CFLAGS += -I${nlohmann_json}/include' \
      --replace-fail 'LDLIBS += -L$(LIBDATACHANNEL_PATH)/build -ldatachannel-static' 'LDLIBS += -ldatachannel' \
      --replace-fail 'LDLIBS += -L$(LIBDATACHANNEL_PATH)/build/deps/usrsctp/usrsctplib -lusrsctp' "" \
      --replace-fail 'LDLIBS += -L$(LIBDATACHANNEL_PATH)/build/deps/libsrtp -lsrtp2' "" \
      --replace-fail 'LDLIBS += -L$(LIBDATACHANNEL_PATH)/build/deps/libjuice -ljuice-static' "" \
      --replace-fail 'camera-streamer: $(LIBDATACHANNEL_PATH)/build/libdatachannel-static.a' 'camera-streamer:'
  '';

  makeFlags = [
    "GIT_VERSION=${version}"
    "GIT_REVISION=${rev}"
    "USE_FFMPEG=1"
    "USE_HW_H264=0"
    "USE_LIBCAMERA=1"
    "USE_LIBDATACHANNEL=1"
    "USE_RTSP=0"
  ];

  installPhase = ''
    runHook preInstall
    install -D -m 0755 camera-streamer $out/bin/camera-streamer
    runHook postInstall
  '';

  meta = {
    description = "Raspberry Pi camera streaming service with WebRTC support";
    homepage = "https://github.com/ayufan/camera-streamer";
    license = lib.licenses.gpl3Only;
    mainProgram = "camera-streamer";
    platforms = lib.platforms.linux;
  };
}
