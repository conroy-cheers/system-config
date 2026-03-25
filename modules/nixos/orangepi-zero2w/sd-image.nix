{
  config,
  modulesPath,
  ...
}:

{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image.nix"
  ];

  sdImage = {
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
