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
    inputs.determinate.darwinModules.default
  ];

  options = {
    corncheese.development = {
      enable = lib.mkEnableOption "corncheese development environment";
      remoteBuilders.enable = lib.mkEnableOption "corncheese remote builders";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        determinateNix = {
          enable = true;
          customSettings = {
            eval-cores = 0;
            extra-experimental-features = [
              "external-builders"
              "parallel-eval"
            ];
            inherit (config.nix.settings)
              extra-substituters
              extra-trusted-public-keys
              trusted-substituters
              ;
          };
        };
        nix = {
          # Let Determinate Nix handle Nix configuration rather than nix-darwin
          enable = false;

          # This will add each flake input as a registry
          # To make nix3 commands consistent with your flake
          registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

          # This will additionally add your inputs to the system's legacy channels
          # Making legacy nix commands consistent as well, awesome!
          nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

          settings = {
            trusted-users = [ "root" ];
            extra-substituters = [
              "https://cache.nixos.org"
              "https://nix-community.cachix.org"
            ];
            extra-trusted-public-keys = [
              "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            ];
          };
        };
      }
      ((lib.mkIf cfg.remoteBuilders.enable) {
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
    ]
  );
}
