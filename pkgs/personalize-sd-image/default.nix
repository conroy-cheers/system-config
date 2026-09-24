{
  lib,
  writeShellApplication,
  python3,
  e2fsprogs,
  openssh,
  zstd,
}:
writeShellApplication {
  name = "personalize-sd-image";
  runtimeInputs = [
    python3
    e2fsprogs
    openssh
    zstd
  ];
  text = ''
    exec python3 ${./personalize.py} "$@"
  '';
  meta = {
    description = "Personalize a NixOS MBR SD image without mounting it";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "personalize-sd-image";
  };
}
