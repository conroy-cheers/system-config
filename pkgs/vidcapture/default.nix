{
  coreutils,
  curl,
  file,
  lib,
  mpv,
  stdenvNoCC,
  systemd,
  ustreamer,
}:

stdenvNoCC.mkDerivation {
  pname = "vidcapture";
  version = "0-unstable-2026-05-21";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 ${./vidcapture-preview} $out/bin/vidcapture-preview
    install -Dm755 ${./vidcapture-snapshot} $out/bin/vidcapture-snapshot
    install -Dm755 ${./vidcapture-keepalive} $out/bin/vidcapture-keepalive
    install -Dm755 ${./vidcapture-watchdog} $out/bin/vidcapture-watchdog
    install -Dm644 ${./vidcapture-keepalive.service.in} $out/lib/systemd/system/vidcapture-keepalive@.service
    install -Dm644 ${./vidcapture-watchdog.service.in} $out/lib/systemd/system/vidcapture-watchdog@.service
    install -Dm644 ${./vidcapture-watchdog.timer.in} $out/lib/systemd/system/vidcapture-watchdog@.timer
    install -Dm644 ${./90-vidcapture-ugreen.rules} $out/lib/udev/rules.d/90-vidcapture-ugreen.rules

    substituteInPlace $out/bin/vidcapture-preview \
      --replace-fail @bash@ ${stdenvNoCC.shell} \
      --replace-fail @mpv@ ${lib.getExe mpv}

    substituteInPlace $out/bin/vidcapture-snapshot \
      --replace-fail @bash@ ${stdenvNoCC.shell} \
      --replace-fail @basename@ ${lib.getExe' coreutils "basename"} \
      --replace-fail @cat@ ${lib.getExe' coreutils "cat"} \
      --replace-fail @cp@ ${lib.getExe' coreutils "cp"} \
      --replace-fail @curl@ ${lib.getExe curl} \
      --replace-fail @dirname@ ${lib.getExe' coreutils "dirname"} \
      --replace-fail @mktemp@ ${lib.getExe' coreutils "mktemp"} \
      --replace-fail @mv@ ${lib.getExe' coreutils "mv"} \
      --replace-fail @rm@ ${lib.getExe' coreutils "rm"} \
      --replace-fail @sleep@ ${lib.getExe' coreutils "sleep"}

    substituteInPlace $out/bin/vidcapture-keepalive \
      --replace-fail @bash@ ${stdenvNoCC.shell} \
      --replace-fail @ustreamer@ ${lib.getExe ustreamer}

    substituteInPlace $out/bin/vidcapture-watchdog \
      --replace-fail @bash@ ${stdenvNoCC.shell} \
      --replace-fail @curl@ ${lib.getExe curl} \
      --replace-fail @file@ ${lib.getExe file} \
      --replace-fail @mktemp@ ${lib.getExe' coreutils "mktemp"} \
      --replace-fail @rm@ ${lib.getExe' coreutils "rm"} \
      --replace-fail @systemctl@ ${lib.getExe' systemd "systemctl"}

    substituteInPlace $out/lib/systemd/system/vidcapture-keepalive@.service \
      --replace-fail @out@ $out

    substituteInPlace $out/lib/systemd/system/vidcapture-watchdog@.service \
      --replace-fail @out@ $out

    runHook postInstall
  '';

  meta = {
    description = "UGREEN capture-card preview and snapshot tools";
    license = lib.licenses.mit;
    mainProgram = "vidcapture-preview";
    platforms = lib.platforms.linux;
  };
}
