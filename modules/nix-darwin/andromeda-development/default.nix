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
  imports = [
    ../../common/andromeda-builders
    ./tailscale.nix
  ];

  options = {
    andromeda.development = {
      enable = mkEnableOption "andromeda development environment";
      nixDaemonSecrets = {
        enable = lib.mkEnableOption "AWS secrets for nix daemon";
      };
      tailscale = {
        enable = lib.mkEnableOption "andromeda tailscale configuration";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      age.secrets = {
        "andromeda.aws-cache.credentials" = {
          rekeyFile = lib.repoSecret "andromeda/aws-cache/credentials.age";
        };
        "andromeda.aws-experiments.key" = mkIf cfg.remoteBuilders.enable {
          rekeyFile = lib.repoSecret "andromeda/aws-experiments/key.age";
          mode = "400";
        };
      };

      system.activationScripts.extraActivation.text =
        let
          awsConfigFile = pkgs.writeText "aws-config" ''
            [default]
            output=json
            region=ap-southeast-2
          '';
        in
        lib.mkBefore ''
          AWS_DIR=~root/.aws

          mkdir -p "$AWS_DIR"
          chmod 700 "$AWS_DIR"

          ln -sf ${config.age.secrets."andromeda.aws-cache.credentials".path} \
            "$AWS_DIR/credentials"
          ln -sf ${awsConfigFile} "$AWS_DIR/config"

          chown -R root:wheel "$AWS_DIR"
        '';

      nix = mkMerge [
        {
          envVars = {
            AWS_DEFAULT_REGION = "ap-southeast-2";
          };
          settings = {
            extra-substituters = [ "s3://andromedarobotics-artifacts?region=ap-southeast-2" ];
            extra-trusted-public-keys = [
              "nix-cache.dromeda.com.au-1:x4QtHKlCwaG6bVGvlzgNng+x7WgZCZc7ctrjlz6sDHg="
            ];
          };
        }
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
  };
}
