{ inputs, lib, pkgs, config, ... }:

{
  environment.systemPackages = with pkgs; [ ];

  corncheese = {
    system.enable = true;
    theming = {
      enable = true;
      theme = "catppuccin";
    };
  };

  users.users.conroy = {
    description = "Conroy Cheers";
    home = "/Users/conroy";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKvtQAUGvh3UmjM7blBM86VItgYD+22HYKzCBrXDsFGB" # conroy
    ];
    shell = pkgs.zsh;
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
