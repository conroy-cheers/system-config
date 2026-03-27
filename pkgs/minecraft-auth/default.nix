{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "minecraft-auth";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    mainProgram = "minecraft-auth";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
