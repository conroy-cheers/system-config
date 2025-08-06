{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.andromeda.development;

  abiUser = "abi";
  abiAliases = {
    "flabi" = "abi-andr-dev-1";
    "agx" = "10.11.120.231";
    "audiobox" = "10.11.4.99";
  };
  abiHostGlobs = [
    "abi-andr-*"
  ];
  abiHosts = builtins.attrNames abiAliases;
  abiRootHosts = map (host: host + "-root") abiHosts;
in
{
  options = {
    andromeda.development = {
      enable = lib.mkEnableOption "andromeda development config";
      tftpServer.enable = lib.mkEnableOption "andromeda tftp dev server";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."andromeda.aws-home-config.credentials" = {
      rekeyFile = "${inputs.self}/secrets/andromeda/aws-home-config/credentials.age";
    };

    home.sessionVariables = {
      ROS_DOMAIN_ID = "38";
    };

    home.file = lib.mkMerge [
      (
        let
          # Get all files from the source directory
          sshFiles = builtins.readDir ./pubkeys;

          # Create a set of file mappings for each identity file
          fileMapper = filename: {
            # Target path will be in ~/.ssh/
            ".ssh/${filename}".source = ./pubkeys + "/${filename}";
          };
        in
        lib.foldl (acc: filename: acc // (fileMapper filename)) { } (builtins.attrNames sshFiles)
        // {
          "${config.home.homeDirectory}/.aws/credentials".source =
            config.lib.file.mkOutOfStoreSymlink
              config.age.secrets."andromeda.aws-home-config.credentials".path;
        }
      )
      {
        ".config/nix-vm/vm.nix" = {
          text = ''
            {
              nixpkgs.hostPlatform = "${pkgs.stdenv.hostPlatform.system}";
              virtualisation.vmVariant = {
                virtualisation = {
                  host.pkgs = import <nixpkgs> { };
                  cores = 4;
                  memorySize = 8192;
                  resolution = { x = 1280; y = 720; };
                };
              };
            }
          '';
        };
      }
    ];

    programs.ssh = {
      enable = true;
      forwardAgent = false;
      hashKnownHosts = true;

      matchBlocks =
        (lib.concatMapAttrs (name: hostname: {
          "${name}".hostname = hostname;
          "${name}-root".hostname = hostname;
        }) abiAliases)
        // {
          abi-dev = {
            host = (lib.concatStringsSep " " (abiHosts ++ abiHostGlobs));
            user = abiUser;
          };
          abi-dev-abi = {
            match = "host ${lib.concatStringsSep "," (abiHosts ++ abiHostGlobs)} user ${abiUser}";
            extraOptions = {
              PubkeyAuthentication = "no";
            };
          };
          abi-dev-root = {
            host = (lib.concatStringsSep " " abiRootHosts);
            user = "root";
            identityFile = "${config.home.homeDirectory}/.ssh/abi_root.id_ed25519.pub";
          };

          "hydraq" = {
            hostname = "hq.dromeda.com.au";
            user = "nixremote";
            port = 8367;
            identityFile = "${config.home.homeDirectory}/.ssh/andromeda_build.id_ed25519.pub";
          };
          "hydra-master" = {
            hostname = "hydra.dromeda.com.au";
            user = "root";
            port = 22;
            identityFile = "${config.home.homeDirectory}/.ssh/andromeda_infra.id_ed25519.pub";
          };
          "build-thing" = {
            hostname = "18.136.8.225";
            user = "root";
            port = 22;
            identityFile = "${config.home.homeDirectory}/.ssh/aws_experiments.id_ed25519.pub";
          };
        };
    };

    programs.awscli = {
      enable = true;
      settings = {
        "default" = {
          region = "ap-southeast-2";
          output = "json";
        };

        "profile iot-crossaccount" = {
          region = "ap-southeast-2";
          output = "json";
        };

        "profile memories-crossaccount" = {
          region = "ap-southeast-2";
          output = "json";
        };

        "profile logs-archive-crossaccount" = {
          region = "ap-southeast-2";
          output = "json";
        };
      };
    };
  };
}
