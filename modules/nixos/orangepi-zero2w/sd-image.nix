{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image.nix"
  ];

  # The native Linux builder shares macOS's case-hacked ncurses store paths.
  # Copy this entry into an unambiguous output instead of embedding a broken
  # l/linux reference. Also works with an ordinary Linux store.
  # https://github.com/NixOS/nixpkgs/issues/550124
  boot.initrd.systemd.contents."/etc/terminfo/l/linux".source = lib.mkForce (
    pkgs.runCommand "linux-console-terminfo" { } ''
      source=${pkgs.ncurses}/share/terminfo/l/linux
      if [ ! -f "$source" ]; then
        source=${pkgs.ncurses}/share/terminfo/l~nix~case~hack~1/linux
      fi
      cp "$source" "$out"
    ''
  );

  sdImage = {
    # The macOS native Linux builder's /build is a small tmpfs. Writing the
    # raw root image straight to $out avoids staging a second copy there.
    compressImage = false;
    rootFilesystemCreator = ./make-ext4-fs.nix;
    populateFirmwareCommands = "";

    populateRootCommands = ''
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} \
        -d ./files/boot
    '';

    postBuildCommands = ''
      dd if=${config.system.build.orangepiZero2wUboot}/u-boot-sunxi-with-spl.bin \
        of=$img bs=1024 seek=8 conv=notrunc
    '';
  };
}
