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
  nixCacheCfNetrcPath = config.age.secrets."andromeda.nix-cache-cf.netrc".path;
  determinateNixdConfig = pkgs.writeText "andromeda-determinate-config.json" (
    builtins.toJSON {
      authentication.additionalNetrcSources = [ nixCacheCfNetrcPath ];
    }
  );
in
{
  imports = [
    ../../common/andromeda-builders
    ./tailscale.nix
  ];

  options = {
    andromeda.development = {
      enable = mkEnableOption "andromeda development environment";
      tailscale.enable = mkEnableOption "andromeda tailnet";
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
      netbootServer = {
        enable = lib.mkEnableOption "andromeda direct-link netboot server";
        connectionName = lib.mkOption {
          description = "Name of the NetworkManager connection used for netbooting";
          type = types.str;
          default = "Andromeda netboot";
        };
        profileName = lib.mkOption {
          description = "Declarative NetworkManager profile name";
          type = types.str;
          default = "andromeda-netboot";
        };
        interface = lib.mkOption {
          description = "Network interface connected to the netboot client";
          type = types.str;
        };
        interfaceMacAddress = lib.mkOption {
          description = "Permanent MAC address of the netboot interface";
          type = types.str;
        };
        serverAddress = lib.mkOption {
          description = "IPv4 address of the netboot server";
          type = types.str;
        };
        prefixLength = lib.mkOption {
          description = "IPv4 prefix length of the direct netboot network";
          type = types.ints.between 0 32;
          default = 24;
        };
        clientAddress = lib.mkOption {
          description = "IPv4 address permitted to mount the netboot NFS root";
          type = types.str;
        };
        tftpRootDirectory = lib.mkOption {
          description = "Root directory to serve over TFTP";
          type = types.str;
        };
        stateDirectory = lib.mkOption {
          description = "Persistent directory containing netboot state";
          type = types.str;
        };
        stateDirectoryOwner = lib.mkOption {
          description = "Owner of the persistent netboot state directory";
          type = types.str;
          default = "root";
        };
        stateDirectoryGroup = lib.mkOption {
          description = "Group of the persistent netboot state directory";
          type = types.str;
          default = "root";
        };
        nfsRootDirectory = lib.mkOption {
          description = "Root directory to export to the netboot client over NFS";
          type = types.str;
        };
        requiredBootFile = lib.mkOption {
          description = "File below the TFTP root that must exist before the server starts";
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
        "andromeda.nix-cache-cf.netrc" = {
          rekeyFile = lib.repoSecret "andromeda/nix-cache-cf/netrc.age";
          mode = "0400";
        };
        "andromeda.aws-experiments.key" = mkIf cfg.remoteBuilders.enable {
          rekeyFile = lib.repoSecret "andromeda/aws-experiments/key.age";
          mode = "400";
        };
        "andromeda.aws-sandbox.key" = mkIf cfg.remoteBuilders.enable {
          rekeyFile = lib.repoSecret "andromeda/aws-sandbox/key.age";
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

      nix = mkMerge [
        {
          settings = {
            netrc-file = nixCacheCfNetrcPath;
            substituters = [
              "https://nix-cache-cf.dromeda.com.au"
            ];
            trusted-public-keys = [
              "nix-cache.dromeda.com.au-1:x4QtHKlCwaG6bVGvlzgNng+x7WgZCZc7ctrjlz6sDHg="
            ];
          };
        }
      ];

      systemd.tmpfiles.rules = [
        "d /root/.aws 0700 root root -"
        "L+ /root/.aws/credentials - - - - ${config.age.secrets."andromeda.aws-cache.credentials".path}"
        "L+ /root/.aws/config - - - - ${pkgs.writeText "andromeda-aws-cache-config" ''
          [default]
          output = json
          region = ap-southeast-2
        ''}"
      ];

      environment.etc."determinate/config.json" = mkIf config.determinate.enable {
        source = determinateNixdConfig;
      };

      systemd.services.nix-daemon.restartTriggers = optional config.determinate.enable determinateNixdConfig;
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
    (mkIf cfg.netbootServer.enable {
      networking.networkmanager.ensureProfiles.profiles.${cfg.netbootServer.profileName} = {
        connection = {
          id = cfg.netbootServer.connectionName;
          type = "ethernet";
          interface-name = cfg.netbootServer.interface;
          autoconnect = true;
          autoconnect-priority = 100;
        };
        ethernet.mac-address = cfg.netbootServer.interfaceMacAddress;
        ipv4 = {
          method = "manual";
          addresses = "${cfg.netbootServer.serverAddress}/${toString cfg.netbootServer.prefixLength}";
          never-default = true;
        };
        ipv6.method = "disabled";
      };

      services.atftpd = {
        enable = true;
        root = cfg.netbootServer.tftpRootDirectory;
        extraOptions = [ "--bind-address ${cfg.netbootServer.serverAddress}" ];
      };

      fileSystems."${cfg.netbootServer.nfsRootDirectory}/nix-store" = {
        device = "/nix/store";
        fsType = "none";
        options = [ "bind" ];
      };

      services.nfs.server = {
        enable = true;
        exports = ''
          ${cfg.netbootServer.nfsRootDirectory} ${cfg.netbootServer.clientAddress}(ro,fsid=0,no_subtree_check,insecure,all_squash,crossmnt)
          ${cfg.netbootServer.nfsRootDirectory}/nix-store ${cfg.netbootServer.clientAddress}(ro,no_subtree_check,insecure,all_squash)
        '';
      };

      systemd.services.atftpd = {
        after = [
          "NetworkManager.service"
          "NetworkManager-ensure-profiles.service"
          "network-online.target"
        ];
        wants = [
          "NetworkManager.service"
          "NetworkManager-ensure-profiles.service"
          "network-online.target"
        ];
        unitConfig.ConditionPathExists = "${cfg.netbootServer.tftpRootDirectory}/${cfg.netbootServer.requiredBootFile}";
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "1s";
        };
      };

      networking.firewall.interfaces.${cfg.netbootServer.interface} = {
        allowedTCPPorts = [ 2049 ];
        allowedUDPPorts = [ 69 ];
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.netbootServer.stateDirectory} 0775 ${cfg.netbootServer.stateDirectoryOwner} ${cfg.netbootServer.stateDirectoryGroup} -"
        "d ${cfg.netbootServer.nfsRootDirectory} 0755 root root -"
        "d ${cfg.netbootServer.nfsRootDirectory}/nix-store 0755 root root -"
      ];

      environment.systemPackages = [ pkgs.atftp ];
    })
  ];

  meta = {
  };
}
