{
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
  ];

  hardware.enableAllHardware = lib.mkForce false;
  sdImage.rootFilesystemCreator = ./make-ext4-fs.nix;

  sdImage.populateFirmwareCommands = lib.mkAfter ''
    chmod u+w firmware/config.txt
    cat <<'EOF' >> firmware/config.txt

    # panda parity with the current MainsailOS image
    enable_uart=1
    dtparam=spi=on
    dtoverlay=disable-bt
    start_x=1
    gpu_mem=256
    dtparam=audio=on
    EOF
  '';
}
