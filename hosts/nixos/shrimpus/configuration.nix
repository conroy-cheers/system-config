{
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/profiles/minimal.nix")
    ../../../modules/nixos/orangepi-zero2w/sd-image.nix
    ./network.nix
    ./diagnostics.nix
  ];

  networking.hostName = "shrimpus";
  time.timeZone = "Australia/Melbourne";

  hardware.orangePiZero2w.enable = true;
  corncheese.development.nebula.enable = false;

  image.baseName = "shrimpus";

  system.disableInstallerTools = true;
  fonts.fontconfig.enable = false;

  # Keep the daemon and remote deployment support, but avoid the larger
  # Determinate distribution and retaining flake source trees through the
  # system registry. Rebuilds pass an explicit flake reference.
  determinate.enable = false;

  nix = {
    registry = lib.mkForce { };
    nixPath = lib.mkForce [ ];
    settings = {
      trusted-users = [ "conroy" ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.users.conroy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      (import ../../../modules/common/corncheese-development/ssh-identities.nix).conroy-home.publicKey
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.05";
}
