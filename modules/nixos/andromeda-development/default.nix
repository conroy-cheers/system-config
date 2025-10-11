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
  imports = [ ./tailscale.nix ];

  options = {
    andromeda.development = {
      enable = mkEnableOption "andromeda development environment";
      tailscale.enable = mkEnableOption "andromeda tailnet";
      remoteBuilders = {
        enable = lib.mkEnableOption "andromeda remote builders";
        useHomeBuilders = lib.mkEnableOption "using home builders by default";
      };
      nixDaemonSecrets = {
        enable = lib.mkEnableOption "AWS secrets for nix daemon";
        nixSandboxKeys = {
          target = lib.mkOption {
            type = with lib.types; path;
            description = "The path to a file containing SOPS keys within the Nix build sandbox.";
            readOnly = true;
          };
        };
      };
      tftpServer = {
        enable = lib.mkEnableOption "andromeda tftp development server";
        rootDirectory = lib.mkOption {
          description = "Root directory to serve over TFTP";
          type = types.str;
        };
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      age.secrets = {
        "andromeda.aws-cache.env" = {
          rekeyFile = "${inputs.self}/secrets/andromeda/aws-cache/env.age";
        };
        "andromeda.aws-experiments.key" = mkIf cfg.remoteBuilders.enable {
          rekeyFile = "${inputs.self}/secrets/andromeda/aws-experiments/key.age";
          mode = "400";
        };
        "andromeda.aws-sandbox.key" = mkIf cfg.remoteBuilders.enable {
          rekeyFile = "${inputs.self}/secrets/andromeda/aws-sandbox/key.age";
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
          
          Host big-chungus
            User root
            HostName 3.106.5.183
            Port 22
            IdentityFile ${config.age.secrets."andromeda.aws-sandbox.key".path}
        '';
      };

      nix = mkMerge [
        {
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
            # {
            #   hostName = "18.136.8.225";
            #   system = "aarch64-linux";
            #   maxJobs = 32;
            #   supportedFeatures = [ "big-parallel" ];
            #   publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUN1RkZBcHZUdjZneHBmRlJZTGFkZnVhdG9hLytBb3V5MjJxSnhjRitDdkQK";
            # }
            # {
            #   hostName = "big-chungus";
            #   system = "x86_64-linux";
            #   speedFactor = 4;
            #   maxJobs = 32;
            #   supportedFeatures = [ "big-parallel" ];
            #   publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVB0NmdlTlEvZmpvYXNpQ1ZPbDYvaFIrSTZ4QTNndE9WNWVtc3NBNHVHeUUK";
            # }
          ];
        })
      ];

      systemd.services.nix-daemon = {
        serviceConfig = {
          EnvironmentFile = [ config.age.secrets."andromeda.aws-cache.env".path ];
        };
        environment = {
          AWS_DEFAULT_REGION = "ap-southeast-2";
        };
      };
    })
    (mkIf cfg.nixDaemonSecrets.enable {
      andromeda.development.nixDaemonSecrets.nixSandboxKeys.target = "/sops/keys.txt";

      # AWS secrets creds for nix-daemon
      age.secrets."andromeda.aws-secrets.env" = {
        rekeyFile = "${inputs.self}/secrets/andromeda/aws-secrets/env.age";
      };
      # sops-nix keys for test VMs
      age.secrets."andromeda.vm-sops-keys.txt" = {
        rekeyFile = "${inputs.self}/secrets/andromeda/vm-sops-keys/keys.age";
        mode = "0440";
        owner = config.users.users.root.name;
        group = config.users.groups.nixbld.name;
      };
      systemd.services.nix-daemon = {
        serviceConfig.EnvironmentFile = [ config.age.secrets."andromeda.aws-secrets.env".path ];
      };

      nix.settings.extra-sandbox-paths = [
        "${cfg.nixDaemonSecrets.nixSandboxKeys.target}=${
          config.age.secrets."andromeda.vm-sops-keys.txt".path
        }"
      ];
      # Make the file available to the Nix daemon directly too, so that
      # non-sandboxed builds can still find it in the expected path.
      systemd.services.nix-daemon.serviceConfig.BindReadOnlyPaths = [
        "${
          config.age.secrets."andromeda.vm-sops-keys.txt".path
        }:${cfg.nixDaemonSecrets.nixSandboxKeys.target}"
      ];
    })
    (mkIf cfg.tftpServer.enable {
      environment.etc."NetworkManager/dnsmasq-shared.d/tftp.conf".text = ''
        pxe-service=0,"Raspberry Pi Boot"
        enable-tftp
        tftp-root=${cfg.tftpServer.rootDirectory}
      '';

      fileSystems = {
        "/export/pi/nix/store" = {
          device = "/nix/store";
          options = [ "bind" ];
        };
      };

      services.nfs.server = {
        enable = true;
        exports = ''
          /export/pi *(crossmnt,ro,insecure,all_squash)
        '';
      };

      networking.firewall.allowedTCPPorts = [
        111
        2049
      ];
      networking.firewall.allowedUDPPorts = [
        111
        2049
      ];
    })
  ];

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
