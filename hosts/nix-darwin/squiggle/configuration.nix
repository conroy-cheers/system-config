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
      themeOverrides = {
        opacity = lib.mkForce 0.92;
        fontSize = lib.mkForce 10;
      };
    };
  };

  nixpkgs = {
    overlays = [
      # If you want to use overlays your own flake exports (from overlays dir):
      inputs.self.overlays.karabiner
    ];
  };

  nix = {
    package = pkgs.nixVersions.monitored.latest;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  programs.zsh.enable = true;

  # Fonts
  fonts.packages = with pkgs; [
    nerd-fonts.meslo-lg
  ];

  services = {
    karabiner-elements = {
      enable = true;
    };
  };

  # Keyboard
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = false;

  system.primaryUser = "conroy";

  # Used for backwards compatibility, please read the changelog before changing.
  # > darwin-rebuild changelog
  system.stateVersion = 5;
}
