{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  sshKey =
    (import ../../../modules/common/corncheese-development/ssh-identities.nix).conroy-home.publicKey;
in
{
  imports = [
    inputs.steam-frame-nixos.nixosModules.default
    ./hardware-configuration.nix
    ./deploy.nix
  ];
  # The flake supplies pkgs with allowUnfree already enabled.
  nixpkgs.config = lib.mkForce { };
  networking.hostName = "bouba";
  time.timeZone = "Australia/Melbourne";
  determinate.enable = false;
  corncheese.development.enable = false;
  corncheese.development.nebula.enable = true;
  corncheese.theming = {
    enable = true;
    theme = "catppuccin";
  };
  nix.registry = lib.mkForce { };
  nix.nixPath = lib.mkForce [ ];
  nix.settings.trusted-users = [
    "root"
    "conroy"
  ];
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];
  users.users.conroy = {
    isNormalUser = true;
    uid = 1000;
    home = "/home/conroy";
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [ sshKey ];
  };
  programs.fish.enable = true;
  security.sudo.wheelNeedsPassword = false;
  services.steam-frame = {
    enable = true;
    user = "conroy";
    desktopSession = null;
  };
  networking.networkmanager.settings.keyfile.path = "/etc/NetworkManager/system-connections";
  environment.systemPackages = with pkgs; [
    git
    rsync
    ethtool
    lm_sensors
    pciutils
    usbutils
    vulkan-tools
  ];
  system.stateVersion = "26.05";
}
