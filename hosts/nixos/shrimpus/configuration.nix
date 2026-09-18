{
  ...
}:

{
  imports = [
    ../../../modules/nixos/orangepi-zero2w/sd-image.nix
  ];

  networking.hostName = "shrimpus";
  time.timeZone = "Australia/Melbourne";

  hardware.orangePiZero2w.enable = true;
  corncheese.development.nebula.enable = false;

  image.baseName = "shrimpus";

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  system.stateVersion = "25.05";
}
