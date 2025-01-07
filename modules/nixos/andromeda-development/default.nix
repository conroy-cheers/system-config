{ inputs, lib, pkgs, config, ... }:

with lib;
let
  cfg = config.andromeda.development;
in
{
  imports = [
    ./tailscale.nix
  ];

  options = {
    andromeda.development = {
      enable = mkEnableOption "andromeda development environment";
      tailscale.enable = mkEnableOption "andromeda tailnet";
      remoteBuilders = {
        enable = lib.mkEnableOption "andromeda remote builders";
        useHomeBuilders = lib.mkEnableOption "using home builders by default";
      };
    };
  };

  config = mkIf cfg.enable {
    age.secrets = {
      "andromeda.aws-cache.env" = {
        rekeyFile = "${inputs.self}/secrets/andromeda/aws-cache/env.age";
      };
      "andromeda.aws-experiments.key" = mkIf cfg.remoteBuilders.enable {
        rekeyFile = "${inputs.self}/secrets/andromeda/aws-experiments/key.age";
        mode = "400";
      };
    };

    programs.ssh = mkIf cfg.remoteBuilders.enable {
      extraConfig = ''
        # build-thing
        Host 18.136.8.225
          User root
          HostName 18.136.8.225
          Port 22
          IdentityFile ${config.age.secrets."andromeda.aws-experiments.key".path}
      '';
    };

    nix = mkMerge [
      {
        settings = {
          substituters = [
            "s3://andromedarobotics-artifacts?region=ap-southeast-2"
          ];
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
            maxJobs = 32;
            supportedFeatures = [ "big-parallel" ];
            publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUN1RkZBcHZUdjZneHBmRlJZTGFkZnVhdG9hLytBb3V5MjJxSnhjRitDdkQK";
          }
        ];
      })
    ];

    systemd.services.nix-daemon.serviceConfig = {
      EnvironmentFile = config.age.secrets."andromeda.aws-cache.env".path;
      Environment = "AWS_DEFAULT_REGION=ap-southeast-2";
    };
  };



  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
