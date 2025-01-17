{ config, lib, pkgs, ... }:

let
  cfg = config.andromeda.development;

  abiUser = "abi";
  abiHostnames = {
    "flabi" = "abi-andr-dev-1";
    "abi2" = "abi-498fc35d";
    "abi3" = "abi-49e564ed";
    "abi10" = "abi-0896ad9a";
    "cubi" = "abi-715240a6";
    "agx" = "10.11.120.231";
  };
  abiHosts = builtins.attrNames abiHostnames;
  abiRootHosts = map (host: host + "-root") abiHosts;
in
{
  options = {
    andromeda.development = {
      enable = lib.mkEnableOption "andromeda development config";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = let
      # Get all files from the source directory
      sshFiles = builtins.readDir ./pubkeys;
      
      # Create a set of file mappings for each identity file
      fileMapper = filename: {
        # Target path will be in ~/.ssh/
        ".ssh/${filename}".source = ./pubkeys + "/${filename}";
      };
    in
      lib.foldl (acc: filename: acc // (fileMapper filename)) {} (builtins.attrNames sshFiles);

    programs.ssh = {
      enable = true;
      forwardAgent = false;
      hashKnownHosts = true;

      matchBlocks = (lib.concatMapAttrs
        (name: hostname: {
          "${name}".hostname = hostname;
          "${name}-root".hostname = hostname;
        })
        abiHostnames) //
      {
        abi-dev = {
          host = (lib.concatStringsSep " " abiHosts);
          user = abiUser;
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
  };
}
