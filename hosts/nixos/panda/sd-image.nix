{
  lib,
  modulesPath,
  pkgs,
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
    uart_2ndstage=1
    dtparam=spi=on
    dtoverlay=disable-bt
    camera_auto_detect=1
    dtparam=audio=on
    EOF

    install -D -m 0644 \
      ${pkgs.linuxPackages_rpi4.kernel}/dtbs/overlays/imx708.dtbo \
      firmware/overlays/imx708.dtbo
  '';
}
