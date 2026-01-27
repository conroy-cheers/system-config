{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:

{
  environment.systemPackages = with pkgs; [ tailscale ];
  services.tailscale.enable = true;

  networking.hostName = "kiki";

  users.users.conroy = {
    uid = 501;
    description = "Conroy Cheers";
    home = "/Users/conroy";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKvtQAUGvh3UmjM7blBM86VItgYD+22HYKzCBrXDsFGB" # conroy
    ];
    shell = pkgs.fish;
  };
  users.knownUsers = [ "conroy" ];

  andromeda = {
    development = {
      enable = true;
      tailscale.enable = true;
    };
  };

  corncheese = {
    system.enable = true;
    brew.enable = true;
    desktop = {
      enable = true;
    };
    yabai = {
      enable = true;
    };
    theming = {
      enable = true;
      theme = "catppuccin";
    };
    development = {
      enable = true;
      remoteBuilders.enable = true;
    };
  };

  nixpkgs = {
    overlays = [
      # If you want to use overlays your own flake exports (from overlays dir):
      inputs.self.overlays.karabiner
    ];
  };

  programs.fish.enable = true;

  # Fonts
  fonts.packages = with pkgs; [ nerd-fonts.meslo-lg ];

  services = {
    karabiner-elements = {
      enable = false;
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
