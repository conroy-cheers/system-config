{
  pkgs,
  lib,
  storePaths,
  compressImage ? false,
  populateImageCommands ? "",
  volumeLabel,
  uuid ? "44444444-4444-4444-8888-888888888888",
}:
let
  image = pkgs.callPackage (pkgs.path + "/nixos/lib/make-ext4-fs.nix") {
    inherit
      storePaths
      compressImage
      populateImageCommands
      volumeLabel
      uuid
      ;
  };
in
image.overrideAttrs (old: {
  # The upstream 20% estimate ran out of space during mkfs -d on the native
  # Linux builder. Count every hardlink and allow more construction headroom.
  # The upstream resize2fs -M step still shrinks the completed filesystem.
  buildCommand =
    assert lib.hasInfix "int($1 * 1.20)" old.buildCommand;
    lib.replaceStrings
      [ "--apparent-size" "int($1 * 1.20)" ]
      [ "--apparent-size --count-links" "int($1 * 2.00)" ]
      old.buildCommand;
})
