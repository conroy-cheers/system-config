{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./network.nix
    ../corncheese-public-services.nix
    inputs.corncheese-server.nixosModules.corncheese-server
  ];

  boot = {
    growPartition = true;
    loader.grub.device = "/dev/vda";
  };

  networking.hostName = "snow";
  time.timeZone = "Australia/Melbourne";

  nix = {
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;
    gc = {
      automatic = true;
      dates = "04:30";
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
      remoteBuilders.enable = false;
    };
    theming = {
      enable = true;
      theme = "catppuccin";
    };
    wm.enable = false;
  };

  corncheese-server = {
    topology = {
      defaultServiceHost = "sleet";
      hosts = {
        sleet.address = "10.1.0.133";
        snow.address = "10.1.1.120";
      };
      ingress.hosts = [
        "snow"
      ];
    };
    ingress.enable = true;
    auth.authelia.enable = true;
    media = {
      enable = true;
      filebrowserQuantum.enable = true;
    };
    games.minecraft.enable = true;
    hydra.enable = true;
    nixCache.enable = true;
  };

  services.traefik.dynamicConfigOptions.tcp = {
    routers.panda-turn = {
      entryPoints = [ "web-secure" ];
      rule = "HostSNI(`turn.home.conroycheers.me`)";
      service = "panda-turn";
      tls.certResolver = "default";
    };
    services.panda-turn.loadBalancer.servers = [
      { address = "10.1.0.133:3478"; }
    ];
  };

  services.mosquitto = {
    enable = true;
    persistence = true;
    dataDir = "/var/lib/mosquitto";
    listeners = [
      {
        port = 1883;
        settings.allow_anonymous = false;
        users.mosquitto = {
          hashedPassword = "$7$101$fVG1AhwRLXPS0i71$CS+AECYd4PVAbVuSSt2WWe0b61ZethYigMDh5MXNV58sJNpZlUvZ9bCgfUEL2qE9GH243Qvd4mL5WywxoyzJ5A==";
          acl = [ "readwrite #" ];
        };
      }
    ];
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
      1883
    ];
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowTcpForwarding = "yes";
    };
  };

  services.qemuGuest.enable = true;

  users.users.conroy = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINKbNTRUenigTtrUSGKImYezWzT/KFOR7dZSpSuvsKNY"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICuABSLmzF3xy8AUA1tqzy11jnkubwbcVALayATZ43fL conroy@brick"
    ];
    shell = pkgs.fish;
    extraGroups = [ "wheel" ];
  };

  programs.fish.enable = true;

  security.sudo-rs = {
    enable = true;
    inherit (config.security.sudo) extraRules;
  };
  security.sudo = {
    enable = false;
    extraRules = [
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
    gitMinimal
    jq
    mosquitto
    vim
  ];

  system.stateVersion = "25.11";
}
