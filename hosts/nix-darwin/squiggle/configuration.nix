{ inputs, lib, pkgs, config, ... }:

{
  environment.systemPackages = with pkgs; [ ];

  users.users.conroy = {
    description = "Conroy Cheers";
    home = "/Users/conroy";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKvtQAUGvh3UmjM7blBM86VItgYD+22HYKzCBrXDsFGB" # conroy
    ];
    shell = pkgs.zsh;
  };

  corncheese = {
    system.enable = true;
    theming = {
      enable = true;
      theme = "catppuccin";
    };
  };

  # log conroy into atuin sync
  age.secrets."corncheese.atuin.key" = {
    rekeyFile = "${inputs.self}/secrets/corncheese/atuin/key.age";
  };
  home-manager.users.conroy = {
    corncheese = {
      shell.atuin.key = config.age.secrets."corncheese.atuin.key".path;
    };
  };

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;

  nix.package = pkgs.nix;

  programs.zsh.enable = true;

  # Fonts
  fonts.packages = with pkgs; [
    nerd-fonts.meslo-lg
  ];

  # Keyboard
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = false;

  # Add ability to use TouchID for sudo authentication
  security.pam.enableSudoTouchIdAuth = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # > darwin-rebuild changelog
  system.stateVersion = 5;
}
