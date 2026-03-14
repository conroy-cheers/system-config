{ lib, config, ... }:

let
  cfg = config.andromeda.development.remoteBuilders;

  buildMachines = [
    {
      # big-chungus-x64
      hostName = "3.106.5.183";
      system = "x86_64-linux";
      speedFactor = 1;
      maxJobs = 32;
      supportedFeatures = [ "big-parallel" ];
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVB0NmdlTlEvZmpvYXNpQ1ZPbDYvaFIrSTZ4QTNndE9WNWVtc3NBNHVHeUUK";
    }
    {
      # big-chungus-aarch64
      hostName = "3.104.252.233";
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

  config = lib.mkIf cfg.enable {
    determinateNix = {
      distributedBuilds = true;
      inherit buildMachines;
    };
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
      # big-chungus-x64
      Host 3.106.5.183
        User ssm-user
        Port 22
        IdentityFile ${config.age.secrets."andromeda.conroy-build.key".path}
        ConnectTimeout 3
        
      # big-chungus-aarch64
      Host 3.104.252.233
        User ssm-user
        Port 22
        IdentityFile ${config.age.secrets."andromeda.conroy-build.key".path}
        ConnectTimeout 3
    '';
  };
}
