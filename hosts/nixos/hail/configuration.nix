{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./network.nix
  ];

  boot.loader.grub = {
    enable = true;
  };

  networking = {
    hostName = "hail";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      interfaces.ens18 = {
        allowedTCPPorts = [ 53 ];
        allowedUDPPorts = [
          53
          4242
        ];
      };
      interfaces."nebula.ccheese" = {
        allowedTCPPorts = [
          22
          53
          5380
        ];
        allowedUDPPorts = [ 53 ];
      };
    };
  };
  time.timeZone = "Australia/Melbourne";

  nix = {
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;
    gc = {
      automatic = true;
      dates = "04:30";
      options = lib.mkForce "--delete-older-than 14d";
    };
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "conroy" ];
    };
  };

  corncheese = {
    development = {
      enable = false;
      githubAccess.enable = false;
      # Enabled after Hail's signed Nebula key is produced through the
      # hardware-backed agenix master identity.
      nebula.enable = false;
      remoteBuilders.enable = false;
    };
    theming = {
      enable = true;
      theme = "catppuccin";
    };
    wm.enable = false;
  };

  services = {
    qemuGuest.enable = true;
    # Technitium owns port 53. Keep resolved for networkd's upstream DNS, but
    # prevent its local stub from blocking Technitium's IPv4 TCP listener.
    resolved.settings.Resolve.DNSStubListener = "no";
    technitium-dns-server.enable = true;
    openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        AllowTcpForwarding = "yes";
      };
    };
  };

  users.users.conroy = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICuABSLmzF3xy8AUA1tqzy11jnkubwbcVALayATZ43fL conroy@brick"
    ];
    shell = pkgs.fish;
    extraGroups = [ "wheel" ];
  };

  programs.fish.enable = true;
  security = {
    sudo.enable = false;
    sudo-rs = {
      enable = true;
      inherit (config.security.sudo) extraRules;
    };
    sudo.extraRules = [
      {
        users = [ "conroy" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };

  environment.systemPackages = with pkgs; [
    curl
    dig
    gitMinimal
    jq
    vim
  ];

  system.stateVersion = "25.11";
}
