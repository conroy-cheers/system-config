{ inputs, config, pkgs, ... }:

{
  age.secrets."andromeda.aws-cache.env" = {
    rekeyFile = "${inputs.self}/secrets/andromeda/aws-cache/env.age";
  };

  systemd.services.nix-daemon.serviceConfig = {
    EnvironmentFile = config.age.secrets."andromeda.aws-cache.env".path;
    Environment = "AWS_DEFAULT_REGION=ap-southeast-2";
  };
}
