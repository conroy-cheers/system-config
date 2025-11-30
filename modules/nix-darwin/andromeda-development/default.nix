{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:

with lib;
let
  cfg = config.andromeda.development;
in
{
  imports = [ ];

  options = {
    andromeda.development = {
      enable = mkEnableOption "andromeda development environment";
      remoteBuilders = {
        enable = lib.mkEnableOption "andromeda remote builders";
        useHomeBuilders = lib.mkEnableOption "using home builders by default";
      };
      nixDaemonSecrets = {
        enable = lib.mkEnableOption "AWS secrets for nix daemon";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      age.secrets = {
        "andromeda.aws-cache.env" = {
          rekeyFile = lib.repoSecret "andromeda/aws-cache/env.age";
        };
        "andromeda.aws-experiments.key" = mkIf cfg.remoteBuilders.enable {
          rekeyFile = lib.repoSecret "andromeda/aws-experiments/key.age";
          mode = "400";
        };
      };

      # TODO restore secrets with Determinate Nix
      # launchd.daemons.nix-daemon.command = lib.mkForce (
      #   pkgs.writeShellScript "nix-daemon-with-secrets" (
      #     lib.concatStringsSep "\n" (
      #       [
      #         "source ${config.age.secrets."andromeda.aws-cache.env".path}"
      #       ]
      #       ++ (lib.optionals cfg.nixDaemonSecrets.enable [
      #         "source ${config.age.secrets."andromeda.aws-secrets.env".path}"
      #       ])
      #       ++ [
      #         (lib.getExe' config.nix.package "nix-daemon")
      #       ]
      #     )
      #   )
      # );

      programs.ssh = mkIf cfg.remoteBuilders.enable {
        extraConfig = ''
          Host big-chungus-x64
            User root
            HostName 3.106.5.183
            Port 22
            IdentityFile ${config.age.secrets."andromeda.aws-sandbox.key".path}

          Host big-chungus-aarch64
            User root
            HostName 3.104.252.233
            Port 22
            IdentityFile ${config.age.secrets."andromeda.aws-sandbox.key".path}
        '';
      };

      nix = mkMerge [
        {
          envVars = {
            AWS_DEFAULT_REGION = "ap-southeast-2";
          };
          settings = {
            substituters = [ "s3://andromedarobotics-artifacts?region=ap-southeast-2" ];
            trusted-public-keys = [
              "nix-cache.dromeda.com.au-1:x4QtHKlCwaG6bVGvlzgNng+x7WgZCZc7ctrjlz6sDHg="
            ];
          };
        }
        (mkIf cfg.remoteBuilders.enable {
          extraOptions = ''
            builders-use-substitutes = true
          '';
          distributedBuilds = true;
          buildMachines = [
            {
              hostName = "18.136.8.225";
              system = "aarch64-linux";
              speedFactor = 4;
              maxJobs = 32;
              supportedFeatures = [ "big-parallel" ];
              publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUN1RkZBcHZUdjZneHBmRlJZTGFkZnVhdG9hLytBb3V5MjJxSnhjRitDdkQK";
            }
            {
              hostName = "big-chungus";
              system = "x86_64-linux";
              maxJobs = 32;
              supportedFeatures = [ "big-parallel" ];
              publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVB0NmdlTlEvZmpvYXNpQ1ZPbDYvaFIrSTZ4QTNndE9WNWVtc3NBNHVHeUUK";
            }
          ];
        })
      ];
    })
    (mkIf cfg.nixDaemonSecrets.enable {
      # AWS secrets creds for nix-daemon
      age.secrets."andromeda.aws-secrets.env" = {
        rekeyFile = lib.repoSecret "andromeda/aws-secrets/env.age";
      };
    })
  ];

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
