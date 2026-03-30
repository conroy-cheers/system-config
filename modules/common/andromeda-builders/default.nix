{
  lib,
  config,
  options,
  ...
}:

let
  cfg = config.andromeda.development.remoteBuilders;
  hasDeterminateBuilders =
    options ? determinateNix
    && options.determinateNix ? buildMachines
    && options.determinateNix ? distributedBuilds;
  hasDeterminateCustomSettings = options ? determinateNix && options.determinateNix ? customSettings;

  buildMachines = [
    {
      hostName = "big-chungus-x86-64";
      system = "x86_64-linux";
      speedFactor = 1;
      maxJobs = 32;
      supportedFeatures = [ "big-parallel" ];
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVB0NmdlTlEvZmpvYXNpQ1ZPbDYvaFIrSTZ4QTNndE9WNWVtc3NBNHVHeUUK";
    }
    {
      hostName = "big-chungus-aarch64";
      system = "aarch64-linux";
      speedFactor = 8;
      maxJobs = 32;
      supportedFeatures = [ "big-parallel" ];
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUVDaGFtWWV2d0wwejc1em1ycXhzMFZuRDlxNCtEcUxiOEZZWFcyV0hlL04K";
    }
  ];
in
{
  options = {
    andromeda.development.remoteBuilders = {
      enable = lib.mkEnableOption "Andromeda remote builders config";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        nix = {
          extraOptions = ''
            builders-use-substitutes = true
          '';
          distributedBuilds = true;
          inherit buildMachines;
        };

        age.secrets = {
          "andromeda.conroy-build.key" = {
            rekeyFile = lib.repoSecret "andromeda/conroy-build/key.age";
            mode = "400";
          };
        };

        programs.ssh.extraConfig = ''
          Host big-chungus-x86-64
            User ssm-user
            Port 22
            IdentityFile ${config.age.secrets."andromeda.conroy-build.key".path}
            ConnectTimeout 3

          Host big-chungus-aarch64
            User ssm-user
            Port 22
            IdentityFile ${config.age.secrets."andromeda.conroy-build.key".path}
            ConnectTimeout 3
        '';
      }
      (lib.optionalAttrs hasDeterminateBuilders {
        determinateNix = {
          distributedBuilds = true;
          inherit buildMachines;
        };
      })
      (lib.optionalAttrs hasDeterminateCustomSettings {
        determinateNix.customSettings.builders-use-substitutes = true;
      })
    ]
  );
}
