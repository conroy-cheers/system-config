{ config, lib, ... }:

let
  abiUser = "abi";
  abiHosts = [ "flabi" "abi2" "abi3" "abi10" ];
  homeJumpHosts = [ "pve" "bigbrain" ];
in  
{
  # Create the bin directory in your home
  # TODO make some hook for this
  # home.file."bin" = {
  #   target = ".local/bin";
  #   recursive = true;
  # };

  # Add the bin directory to PATH if it's not already there
  home.sessionVariables = {
    PATH = "${config.home.homeDirectory}/.local/bin:$PATH";
  };

  # Helper script to save SSH public keys from 1Password
  home.file.".local/bin/save-op-ssh-keys" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      
      echo "Updating SSH public key files from 1Password..."
      umask 077 && op item get abi-root --fields "public key" > ${config.home.homeDirectory}/.ssh/abi_root.id_ed25519.pub
      umask 077 && op item get andromeda-infra --fields "public key" > ${config.home.homeDirectory}/.ssh/andromeda_infra.id_ed25519.pub
      umask 077 && op item get andromeda-build --fields "public key" > ${config.home.homeDirectory}/.ssh/andromeda_build.id_ed25519.pub
      umask 077 && op item get aws-experiments --fields "public key" > ${config.home.homeDirectory}/.ssh/aws_experiments.id_ed25519.pub
      umask 077 && op item get conroy-work --fields "public key" > ${config.home.homeDirectory}/.ssh/conroy_work.id_ed25519.pub

      umask 077 && op item get conroy-home --fields "public key" > ${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub
    '';
  };

  programs.ssh = {
    enable = true;
    forwardAgent = false;
    hashKnownHosts = true;

    matchBlocks = {
      # Work
      "flabi-root" = {
        hostname = "abi-8152c13f";
        user = "root";
        identityFile = "${config.home.homeDirectory}/.ssh/abi_root.id_ed25519.pub";
      };
      "flabi".hostname = "abi-8152c13f";
      "abi2".hostname = "abi-498fc35d";
      "abi3".hostname = "abi-49e564ed";
      "abi10".hostname = "abi-0896ad9a";
      abi-dev = {
        host = (lib.concatStringsSep " " abiHosts);
        user = abiUser;
        extraOptions = {
          PubkeyAuthentication = "no";
        };
      };

      "hydraq" = {
        hostname = "hq.dromeda.com.au";
        user = "abi";
        port = 8367;
        identityFile = "${config.home.homeDirectory}/.ssh/andromeda_build.id_ed25519.pub";
      };
      "hydra-master" = {
        hostname = "hydra.dromeda.com.au";
        user = "root";
        port = 22;
        identityFile = "${config.home.homeDirectory}/.ssh/andromeda_infra.id_ed25519.pub";
      };

      # Home
      "beluga" = {
        hostname = "corncheese.org";
        user = "conroycheers";
        identityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
      };
      "pve" = {
        hostname = "10.1.1.3";
        user = "root";
        identityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
      };
      "bigbrain" = {
        hostname = "bigbrain.lan";
        user = "conroy";
        identityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
      };
      home = {
        host = (lib.concatStringsSep " " homeJumpHosts);
        proxyJump = "beluga";
      };
    };
  };
}