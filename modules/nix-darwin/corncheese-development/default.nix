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
  imports = [ ];

  options = {
    corncheese.development = {
      enable = lib.mkEnableOption "corncheese development environment";
      remoteBuilders.enable = lib.mkEnableOption "corncheese remote builders";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        nix = {
          package = pkgs.nixVersions.monitored.latest;

          # Enable flakes, the new `nix` commands and better support for flakes in it
          extraOptions = ''
            experimental-features = nix-command flakes
          '';

          # This will add each flake input as a registry
          # To make nix3 commands consistent with your flake
          registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

          # This will additionally add your inputs to the system's legacy channels
          # Making legacy nix commands consistent as well, awesome!
          nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

          settings = {
            trusted-users = [ "root" ];

            # Add nix-community cachix cache
            substituters = [ "https://nix-community.cachix.org" ];
            trusted-public-keys = [
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            ];
          };
        };
      }
      ((lib.mkIf cfg.remoteBuilders.enable) {
        age.secrets = {
          "corncheese.home.key" = {
            rekeyFile = "${inputs.self}/secrets/corncheese/home/key.age";
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
          distributedBuilds = true;
          buildMachines = [
            {
              hostName = "home.conroycheers.me";
              system = "x86_64-linux";
              maxJobs = 28;
              supportedFeatures = [ "big-parallel" ];
              publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVAxVXltZktkZHYrWXZ3RlJRRE9YLzZHNFVYWFQ2bEFnNGtHU0tOczc0WE8gcm9vdEBiaWdicmFpbgo=";
            }
          ];
        };
      })
    ]
  );
}
