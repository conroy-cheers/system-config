{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ tailscale ];
  homebrew.casks = [
    "karabiner-elements"
    "prusaslicer"
  ];
  services.tailscale.enable = true;

  networking.hostName = "kiki";

  users.users.conroy = {
    uid = 501;
    description = "Conroy Cheers";
    home = "/Users/conroy";
    shell = pkgs.fish;
  };
  users.knownUsers = [ "conroy" ];

  nix = {
    settings = {
      trusted-users = [ "conroy" ];
    };
  };

  andromeda = {
    development = {
      enable = true;
      tailscale.enable = true;
      remoteBuilders.enable = true;
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
      githubAccess.enable = true;
      remoteBuilders.enable = true;
    };
  };

  programs.fish.enable = true;

  # Fonts
  fonts.packages = with pkgs; [ nerd-fonts.meslo-lg ];

  # Keyboard
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = false;

  system.primaryUser = "conroy";

  # Used for backwards compatibility, please read the changelog before changing.
  # > darwin-rebuild changelog
  system.stateVersion = 5;
}
