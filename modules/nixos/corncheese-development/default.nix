{
  lib,
  inputs,
  pkgs,
  config,
  ...
}:

let
  cfg = config.corncheese.development;
in
{
  imports = [
    ./virtualisation.nix
    inputs.vscode-server.nixosModules.default
    # Determinate
    inputs.determinate.nixosModules.default
  ];

  options = {
    corncheese.development = {
      enable = lib.mkEnableOption "corncheese development environment";
      githubAccess.enable = lib.mkEnableOption "GitHub access token for the Nix daemon";
      remoteBuilders.enable = lib.mkEnableOption "corncheese remote builders";
      tailscale.enable = lib.mkEnableOption "corncheese tailnet";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable || cfg.githubAccess.enable) {
      age.secrets = {
        "corncheese.github.token" = {
          rekeyFile = lib.repoSecret "corncheese/github/token.age";
          mode = "400";
        };
      };

      age-template.files = {
        "nix.extra-access-tokens.conf" = {
          vars = {
            githubConfig = config.age.secrets."corncheese.github.token".path;
          };
          content = ''
            $githubConfig
          '';
          path = "/etc/nix/nix.extra-access-tokens.conf";
          mode = "0444";
        };
      };

      nix.extraOptions = ''
        !include ${builtins.baseNameOf config.age-template.files."nix.extra-access-tokens.conf".path}
      '';
    })
    (lib.mkIf cfg.enable {
      nix = {
        # This will add each flake input as a registry
        # To make nix3 commands consistent with your flake
        registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

        # This will additionally add your inputs to the system's legacy channels
        # Making legacy nix commands consistent as well, awesome!
        nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

        settings = {
          trusted-users = [ "root" ];
          # Enable flakes, the new `nix` commands and better support for flakes in it
          experimental-features = [
            "nix-command"
            "flakes"
          ];

          eval-cores = 0;
        };
      };

      # Fix VSCode server
      services.vscode-server.enable = true;

      environment.systemPackages = [
        pkgs.can-utils
      ];
    })
    (lib.mkIf cfg.remoteBuilders.enable {
      age.secrets = {
        "corncheese.home.key" = {
          rekeyFile = lib.repoSecret "corncheese/home/key.age";
          mode = "400";
        };
      };
      programs.ssh = {
        extraConfig = ''
          # bigbrain-direct
          Host home.conroycheers.me
            User conroy
            HostName home.conroycheers.me
            Port 8022
            IdentityFile ${config.age.secrets."corncheese.home.key".path}
        '';
      };
      nix = {
        extraOptions = ''
          builders-use-substitutes = true
        '';
      };
    })
    (lib.mkIf cfg.tailscale.enable {
      # make the tailscale command usable to users
      environment.systemPackages = [ pkgs.tailscale ];
      # enable the tailscale service
      services.tailscale.enable = true;
    })
  ];
}
