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
        "andromeda.aws-cache.credentials" = {
          rekeyFile = lib.repoSecret "andromeda/aws-cache/credentials.age";
        };
        "andromeda.aws-experiments.key" = mkIf cfg.remoteBuilders.enable {
          rekeyFile = lib.repoSecret "andromeda/aws-experiments/key.age";
          mode = "400";
        };
        "andromeda.aws-sandbox.key" = mkIf cfg.remoteBuilders.enable {
          rekeyFile = lib.repoSecret "andromeda/aws-sandbox/key.age";
          mode = "400";
        };
        "andromeda.conroy-build.key" = mkIf cfg.remoteBuilders.enable {
          rekeyFile = lib.repoSecret "andromeda/conroy-build/key.age";
          mode = "400";
        };
        "andromeda.aws-sandbox.sso-config" = mkIf cfg.remoteBuilders.enable {
          rekeyFile = lib.repoSecret "andromeda/aws-sandbox/sso-config.age";
          mode = "444";
        };
      };

      programs.nix-ld = {
        enable = true;
      };

      networking.interfaces.lo.ipv4.routes = [
        {
          address = "224.0.0.0";
          prefixLength = 4;
        }
      ];

      environment.systemPackages = [
        pkgs.awscli2
        pkgs.ssm-session-manager-plugin
        (pkgs.writeShellScriptBin "builder-sso-login" ''
          sudo AWS_CONFIG_FILE=${
            config.age.secrets."andromeda.aws-sandbox.sso-config".path
          } aws sso login --no-browser
        '')
      ];

      programs.ssh = mkIf cfg.remoteBuilders.enable {
        extraConfig = ''
          # big-chungus-x64
          Host 3.106.5.183
            User root
            Port 22
            #ProxyCommand sh -c "AWS_CONFIG_FILE=${
              config.age.secrets."andromeda.aws-sandbox.sso-config".path
            } aws ssm start-session --target i-03600f75857b7aaaf --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
            IdentityFile ${config.age.secrets."andromeda.conroy-build.key".path}
            ConnectTimeout 3
            
          # big-chungus-aarch64
          Host 3.104.252.233
            User root
            Port 22
            #ProxyCommand sh -c "AWS_CONFIG_FILE=${
              config.age.secrets."andromeda.aws-sandbox.sso-config".path
            } aws ssm start-session --target i-01aa96b81201c1463 --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
            IdentityFile ${config.age.secrets."andromeda.conroy-build.key".path}
            ConnectTimeout 3
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
        })
      ];

      systemd.services.nix-daemon = {
        serviceConfig = {
          BindReadOnlyPaths = [
            "${config.age.secrets."andromeda.aws-cache.credentials".path}:/root/.aws/credentials"
            "${pkgs.writeText "andromeda-aws-cache-config" ''
              [default]
              output=json
              region=ap-southeast-2
            ''}:/root/.aws/config"
          ];
        };
      };
    })
    (mkIf cfg.nixDaemonSecrets.enable {
      andromeda.development.nixDaemonSecrets.nixSandboxKeys.target = "/sops/keys.txt";

      # AWS secrets creds for nix-daemon
      age.secrets."andromeda.aws-secrets.env" = {
        rekeyFile = lib.repoSecret "andromeda/aws-secrets/env.age";
      };
      # sops-nix keys for test VMs
      age.secrets."andromeda.vm-sops-keys.txt" = {
        rekeyFile = lib.repoSecret "andromeda/vm-sops-keys/keys.age";
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
